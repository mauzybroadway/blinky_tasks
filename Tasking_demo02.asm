@; Tasking_demo02.asm wmh 2015-04-27 : adds _t_start, t_end SVC calls 
@;  - 'tasks' are functions which are called during program execution
@;	- a task has the following format:
@;	void some_task(arg1, arg2, ...) //tasks can have 0-3 arguments
@;	{
@;		T_START ;	//macro inline assembler SVC call to the task start service 
@;		...			//ordinary function code
@;		T_SLEEP ;	//macro inline assembler SVC call to the task suspend service 
@;		T_WAIT ;	//macro inline assembler SVC call to interrupt dispatch service
@;		...			//ordinary function code
@;		...			//ordinary function code
@;		T_FINISH ;	//macro inline assembler SVC call to the task finish service  
@;	}	//exit occurs through SVC #FF, not here
@;
@;
@;	
@; Tasking_demo01.asm wmh 2015-04-22 : support for tasking
	.syntax unified				@; ARM Unified Assembler Language (UAL). 
								@; Code written using UAL can be assembled 
						@; for ARM, Thumb-2, or pre-Thumb-2 Thumb
	.thumb				@; Use thmb instructions only	

	.extern __cs3_stack	@;stack base at top of system memory
	
	@;************** constant and structure definitions
		@;configuration constants
		.equ T_NUM, 2		@;number of task descriptors in task list
		.equ T_SSIZE,16		@;task slot size (see field offsets T_ID, T_BASE, T_TIME, T_SP defined below)

		@;data structure of a task 'slot' 
		@; Nothing sacred about choices -- should probably have more but I want 
		@; power-of-2 size for indexing into an array of them. 
		.equ T_ID,0			@;offset in task descriptor 'slot' to task ID field
		.equ T_BASE,4		@; ""                                stack base
		.equ T_TIME,8		@; ""                                time allocation
		.equ T_SP,12		@; ""                                'context' pointer

	@;***************** global variables (must be initialized before use)
	.bss				@;start in uninitialized RAM data section				 
	.align	2			@;pad memory if necessary to align on word boundary (2**2) for word storage

	@;global task control variables	
@;	.global task_control
@;task_control:
	.comm current_task,4		@;holds task ID = offset/4 of current task in 'tasks' list
	.comm tasks,(T_NUM*T_SSIZE)	@;task control structure (see definitions above for internal structure)	

	@;**************** tasking functions 
	.text

	@;*** void TaskSlot_inits(); //call in main before start of tasking to initialize the task commutator
	@;writes initial contents of slots, installs 'main()' as task0
	.global TaskSlot_inits	
	.thumb_func
TaskSlot_inits:	@;initialize task slots for the two tasks of this example
	ldr r0,=tasks					@;r0= address of task control structure/address of 'main()' slot	
	mov r1,#0						@;keep a zero handy in r1
	@;make task #0 the first 'current_task' so that 'main()'s context will be saved on the first PendSV interrupt
	str r1,[r0,#-4]					@; ..
	@;initialize slot 0 for main()
	ldr r2,=__cs3_stack				@;main()'s stack base
	str r1,[r0,#T_ID]				@;initialize main()'s task ID  (not used so far)
	str r2,[r0,#T_BASE]				@; ""                 stack base at system startup value
	str r1,[r0,#T_TIME]				@; ""                 time allocation (not used so far))
	str r1,[r0,#T_SP]				@; ""                 context pointer (will be overwritten on first PendSV)
	@;initialize slot 1 for demo_task()
	add r0,#T_SSIZE					@;step to Task 1's slot
	sub r2,#0x0800					@;allocate 2 kB for  main()'s stack before start of task 1's stack
	str r1,[r0,#T_ID]				@;initialize main()'s task ID  (not used so far)
	str r2,[r0,#T_BASE]				@; ""                 stack base at system startup value
	str r1,[r0,#T_TIME]				@; ""                 time allocation (not used so far))
	str r1,[r0,#T_SP]				@; ""                 

	bx lr							@;done -- task slots (but not task contexts) are initialized

	
	
	@;*** task_context_init_trap(); //for debug -- never returns
	.global task_context_init_trap
	.thumb_func
task_context_init_trap:	@;//catches exit error (if any) of first time use of task context
	b .					@;gets stuck here forever

	@;void task_context_init(int slotID, void (*task)(void)); //builds initial stack of a task; return task starting SP/NULL if fail
	.global old_task_context_init	
	.thumb_func
old_task_context_init: 
	@;build stack picture simulating interrupt stack 
	MRS r2, PSR						@; xPSR with Thumb state 'T' bit set (task return must be to Thumb state)
	orr r2, #(0x01<<24)				@; ..
	stmdb r0,{r2}					@; ..
	stmdb r0,{r1}					@; PC
	adr r2,task_context_init_trap	@; LR 
	stmdb r0,{r2}					@; ..
	mov r2,#0						@;register r12, r3-r0 initial values 
	stmdb r0,{r2}					@; R12
	stmdb r0,{r2}					@; R3
	stmdb r0,{r2}					@; R2
	stmdb r0,{r2}					@; R1
	stmdb r0,{r2}					@; R0
	@;save remainder of CPU's registers
	stmdb r0,{r2}					@; R11
	str r2,[r0,#-4]!
	stmdb r0,{r2}					@; R10
	stmdb r0,{r2}					@; R9
	stmdb r0,{r2}					@; R8
	stmdb r0,{r2}					@; R7
	stmdb r0,{r2}					@; R6
	stmdb r0,{r2}					@; R5
	stmdb r0,{r2}					@; R4
	@;return task context pointer to caller
	bx lr							@;return with context pointer in r0

	
	@;*** void *add_task(void *t_base, void (task*)(void),void *slot_ptr, ); //build starting stack of task at base; return task starting SP/NULL if fail
	.thumb_func
add_task:
	push {r2}				@; preserve slot_ptr value
@;!!	bl task_context_init	@;build starting stack of task at t_base; return task starting SP in r0
	pop	 {r2}				@;restore slot pointer in {r2}
	str	r0,[r2,#T_SP]		@;task's starting stack pointer is initialized
	bx lr					@;return after doing the minimum (fancier version would initialize other parts of slot)	

	@;*** void PendSV_Handler(void); //tasking interrupt; saves current task's context, selects and dispatches next task	
	@; questions:
	@;	- should the change-over between stack pointers be atomic? 
	
	.global PendSV_Handler	
	.thumb_func
PendSV_Handler:		
	@;save context of current task
	push {r4-r11}			@;other registers have already been saved by PendSV, now save the remainder
	ldr r0,=(tasks)			@;pointer to 'tasks' in r0
	ldr r1,[r0,#-4]			@;slot# of current task in r1
	add r2,r0,r1,LSL #4		@;point to current task slot in r2
	str sp,[r2,#T_SP]		@;save current task's context in its slot

	@;select next task
	@;	.. your code which changes slot-pointer stored in 'current' goes here ...
	@;phony 'select next task' provided here by Hawkins just toggles between task 0 and task 1
	ldr r0,=(tasks)			@;pointer to 'tasks' in r0
	ldr r1,[r0,#-4]			@;slot# of current task in r1
	add r1,#1				@;toggle it
	and r1,#1				@; ..
	str r1,[r0,#-4]			@;slot# of new task in r1
	@;here at end of Hawkins' phony 'select next task'
	
	@;restore context of next task
	ldr r0,=(tasks)			@;pointer to 'tasks' in r0
	ldr r1,[r0,#-4]			@;slot# of starting task in r1
	add r2,r0,r1,LSL #4		@;point to starting task slot in r2
	ldr sp,[r2,#T_SP]		@;get starting task's context from its slot
	pop {r4-r11}			@;load partial context of new task
	bx lr					@;'finish interrupt' effect loads remaining context of new task and resumes into new task
	
	
	.ltorg
	
	
	
