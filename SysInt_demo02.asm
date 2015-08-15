@; SysInt_demo02.asm wmh 2015-04-24 : adds tasking to demo; 
@;	PendSV_Handler now swaps in task LED_all()'s context and dispatches it, then saves its context and resumes execution in main()'s context
@; SysInt_demo01.asm wmh 2015-03-02 : demonstration SysTick_init, SvcHandler_init, PendSV_init, SvcHandler, PendSV_Handler
@; derives frpm stm32f4xx_SYSINT_03.asm
@; What was learned:
@;  - SVC can't use SVC -- a usage fault (or hard fault if usage fault is not enabled) will be generated.
@;  - PendSV can used to defer requests to switch task context from both SysTick interrupts and SVC calls and thus avoid
@;    preempting/delaying a hardware interrupt with a SysTick or SVC task-switch call.  
@;  How? If either SysTick or SVC are called to switch tasks they can instead 
@;	set up data for the task-switch to be done by PendSV, then set PendSV flag and return.  If what is being returned to is a task
@;  then PendSV will fire and execution will switch to the new task. If what is being returned to is an IRQ, then because PendSV's priority
@;  has been set lower (the assumption) than all other IRQs, the task switch will be deferred until all of the other IRQs are processed.   
@; 

	.extern SysTick_count	@;not used
	.extern PendSV_counter	@;not used
	
@; --- characterize target syntax, processor
	.syntax unified				@; ARM Unified Assembler Language (UAL). 
	.thumb						@; Use thumb instructions only

@;*** definitions *** 


@; NVIC interrupt control registers -- not used for system interrupts
@;	.equ NVIC_ISERbase,0xE000E100		@;Interrupt Set-Enable register base; registers 0-7 at offsets 0-0x1C w step=4 (ref: DDI0439D trm pg 64)
@;	.equ NVIC_ICERbase,0xE000E180		@;Interrupt Clear-Enable register base;""
@;	.equ NVIC_ISPbase,0xE000E200		@;Interrupt Set-Pending register base; ""
@;	.equ NVIC_ICPbase,0xE000E280		@;Interrupt Clear-Pending register base; ""
@;	.equ NVIC_IABbase,0xE000E300		@;Interrupt Active Bit register base; ""
@;	.equ NVIC_IPRbase,0xE000E400		@;Interrupt Priority register base; registers 0-7 at offsets 0-0xEC step=32 (ref: DDI0439D trm pg 64)

@; system interrupt numbers are of academic interest (only) -- we dont use them
@;	.equ SvcHandlerExcep,-4
@;	.equ PendSVExcep,-2
@;	.equ SysTickExcep,-1
	
@;*** macros ***
@; desiderata : 
@;	- no side effects other than scratch registers
@;	- no local pool 'out of range' (i.e. use immediate values)

.macro MOV_imm32 reg val		@;example of use: MOV_imm32 r0,0x12345678 !!note: no '#' on immediate value
	movw \reg,#(0xFFFF & (\val))
	movt \reg,#((0xFFFF0000 & (\val))>>16)
.endm

@; --- begin code memory
	.text						@;start the code section

	.equ SYST_CSR,0xE000E010 	@;SysTick Control and Status Register ref: DDI0403D B3.3.2

	.global SysTick_init
	.thumb_func
SysTick_init:
	MOV_imm32 r1,SYST_CSR		@;get SysTick control register base
	@;stop SysTick counter before making changes
	MOV_imm32 r2,0x0 			
	str r2,[r1]
	@;set SysTick period
	MOV_imm32 r2,0x493E		@;!!fix (this is the ST_CALIB 'TENMS' value we got from looking in Keil debugger Peripherals > System Tick Timer) 		
	str r2,[r1,#4]			@;SysTick Reload Value Register, SYST_RVR
	@;clear current count
	str r2,[r1,#8]			@;SysTick Current Value Register, SYST_CVR (storing any value does it)
	@;initial test -- enable the counter using core clock, don't enable interrupt
	mov r2,0x05
	str r2,[r1,#0]
	
	bx lr

	
@;initial verification of SysTick counter settings and other hardware before using SysTick interrupt 
	.global SysTick_wait @; void SysTick_wait(int numticks); //return after numticks of Systick
	.thumb_func
SysTick_wait:	@;!!unsafe -- hangs if SysTick is not running
	ldr r1,=SysTick_count  		@;get current SysTick_count
	ldr r3,[r1]					@; ..
	MOV_imm32 r1,SYST_CSR		@;get SysTick control register base
1:	ldr r2,[r1,#0]				@;read Systick status (sutomatic reset of COUNTFLAG
	ands r2,#(1<<16)			@;test SysTick status flag COUNTFLAG 
	beq 1b 						@;block until SysTick timer sets COUNTFLAG
	add r3,#1					@;increment SysTick_count
	subs r0,#1					@;decrement numticks
	bne 1b						@;block until numticks is exhausted
	ldr r1,=SysTick_count  		@;update current SysTick_count
	str r3,[r1]					@; ..
	
	bx lr
	
	@;registers used for SysTick, SVC, and PendSV initializations, drawn from DDI0439 and DDI0403D
	.equ SCR,0xE000ED10			@;System Control Register
	.equ CCR,0xE000ED14			@;Configuration and Control Register.
	.equ SHPR1,0xE000ED18		@;System Handler Priority Register 1
	.equ SHPR2,0xE000ED1C		@;System Handler Priority Register 2
	.equ SHPR3,0xE000ED20		@;System Handler Priority Register 3
	.equ SHCSR,0xE000ED24		@;System Handler Control and State Register

	.equ ICSR,0xE000ED04		@;Interrupt Control and State Register
	.equ PENDSVSET,28			@; bit location in ICSR to set PendSV interrupt pending
	.equ PENDSVCLR,27			@; ""					 clear PendSV ""
	
	.equ SysTick_PR,SHPR3+3		@;DDI0403D section B3.2.12
	.equ PendSV_PR,SHPR3+2		@; ""
	.equ SvcHandler_PR,SHPR2+3	@;DDI0403D section B3.2.11



@;SysTick interrupt hardware setup. !!Must also edit IRQ vector table 
	.global SysTickIRQ_init
	.thumb_func
SysTickIRQ_init: 	@;void SysTickIRQ_init(int priority); //configure SysTick timer and interrupt with 0x00<priority<0xF0 (low four bits are ignored)

	MOV_imm32 r1,SYST_CSR		@;get SysTick control register base
	@;stop SysTick counter and interrupt before making changes
	mov r2,0x0 					
	str r2,[r1]
	@;set SysTick period
	MOV_imm32 r2,0x493E		@;!!fix? (this is the ST_CALIB 'TENMS' value we got from looking in Keil debugger Peripherals > System Tick Timer) 		
	str r2,[r1,#4]			@;SysTick Reload Value Register, SYST_RVR
	@;clear current SysTick count
	str r2,[r1,#8]			@;SysTick Current Value Register, SYST_CVR (storing any value does it)
	@;establish SysTick priority
	MOV_imm32 r3,SysTick_PR	@;byte-address of SysTick priority register
	and r0,0xF0				@;only upper 4 bits of STM32F407 priority are used
	strb r0,[r3]			@;
	@;enable interrupt, enable the counter using core clock
	mov r2,0x07
	str r2,[r1,#0]
	
	bx lr

@;SvcHandler interrupt hardware setup. !!Must also edit IRQ vector table 
	.global SvcHandler_init
	.thumb_func
SvcHandler_init: 	@;void SvcHandler_init(int priority); //configure SVC interrupt with 0x00<priority<0xF0 (low four bits are ignored)
	MOV_imm32 r1,SYST_CSR		@;get SysTick control register base
	@;establish SVC priority
	MOV_imm32 r3,SvcHandler_PR	@;byte-address of SVC priority register
	and r0,0xF0					@;only upper 4 bits of STM32F407 priority are used
	strb r0,[r3]				@;
	
	bx lr

	.global SvcHandler
	.thumb_func
SvcHandler: 	@;silly SVC interrupt function uses SVC #1,#2 to update msTicks; SVC #0 calls PendSV to change LED outputs
@;entered from SVC call with critical registers saved ala Cortex-M3 interrupt
@; (note: if this is to be used with arguments (not recommended) or to return arguments, those will be found in the stack
@; assumes that main stack is being used
	ldr r1,[sp,#24]			@;r1 gets program counter where SVC call was issued	
	ldrb r0,[r1,#-2]		@;r0 has SVC# in low byte 
	uxtb r0,r0				@; turn it into an int  
	ldr r1,=msTicks			@;update counter by adding SVC# to it
	ldr	r2,[r1]				@; ..
	add r2,r0				@; ..
	str	r2,[r1]				@; ..
	cmp r0,#0				@; for the special case of SVC#=0, set PendSV interrupt flag
	bne 1f					@; ..
	@;set PendSV
	ldr r1,=ICSR			@;Interrupt Control and State Register
	mov r0,(1<<PENDSVSET)	@;PendSV set bit 	
	str r0,[r1]
	
1:	bx lr					@;automatic restore context and stack and resume program

@; silly SVC handler demos -- functions to implement SVC #'s 0-2 to be used with SvcHandler (above) to write display values in main()
	.global SVC_0			@;executes SVC #0 and returns
	.thumb_func
SVC_0:
	svc #0
	bx lr
	
	.global SVC_1			@;executes SVC #1 and returns
	.thumb_func
SVC_1:
	svc #1
	bx lr
	
	.global SVC_2			@;executes SVC #2 and returns
	.thumb_func
SVC_2:
	svc #2
	bx lr
	
@;PendSV interrupt hardware setup. !!Must also edit IRQ vector table 
	.global PendSV_init
	.thumb_func
PendSV_init: 	@;void PendSV_init(int priority); //configure PendSV interrupt with 0x00<priority<0xF0 (low four bits are ignored)
@;PendSV priority should be lowest (highest numerical) so it only occurs if no other interrupts are running
	MOV_imm32 r1,SYST_CSR		@;get SysTick control register base !!what does this do/why is this here?
	@;establish SVC priority
	MOV_imm32 r3,PendSV_PR	@;byte-address of PendSV priority register
	and r0,0xF0					@;only upper 4 bits of STM32F407 priority are used
	strb r0,[r3]				@;
	
	bx lr

	@;PendSV_Handler below has been replaced with one defined in Tasking_demo01.asm
	.global oldPendSV_Handler @;	void PendSV_Handler(void); called by SVC #0; writes LEDs to all 'ON'
	.thumb_func
oldPendSV_Handler:	@;triggered as an interrupt when SVC_0 sets PendSV flag; produces same effect as button press in main()
	push {lr} 		@;save interrupt-return 'funny number' in case the function called (LED_ALL) doesn't 
	mov r0,0x0F		@;call a function to turn on all four LEDs
	bl LED_All		@; ..
	pop {pc}		@;load 'funny number' into pc and trigger PendSV return		
	
	.ltorg	@;create a literal pool here for constants defined above. 
