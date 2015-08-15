REM  makeSTM32F4Blinky.bat wmh 2015-03-02 : Blinky with SysTick, SvcHandler and PendSV  
set path=.\;C:\yagarto\bin;

REM assemble with '-g' omitted where we want to hide things in the AXF
REM  arm-none-eabi-as -g -mcpu=cortex-m4 -o aDemo.o CortexM4asmOps_01.asm
  arm-none-eabi-as -g -mcpu=cortex-m4 -o aStartup.o SimpleStartSTM32F4_03.asm
  arm-none-eabi-as -g -mcpu=cortex-m4 -o aSysIntDemo.o SysInt_demo03.asm
  arm-none-eabi-as -g -mcpu=cortex-m4 -o aTasking.o Tasking_demo02.asm
pause

REM compiling C
  arm-none-eabi-gcc -I./  -c -mthumb -O0 -g -mcpu=cortex-m4 -save-temps STM32F4main03.c -o cMain.o
  arm-none-eabi-gcc -I./  -c -mthumb -O0 -g -mcpu=cortex-m4 -save-temps LED_02.c -o cLED.o
pause

REM linking
 arm-none-eabi-gcc -nostartfiles -g -Wl,--no-gc-sections -Wl,-Map,Blinky.map -Wl,-T -Wl,linkBlinkySTM32F4_01.ld -oBlinky.elf aStartup.o aSysIntDemo.o aTasking.o cLED.o cMain.o -lgcc
pause

REM hex file
  arm-none-eabi-objcopy -O ihex Blinky.elf Blinky.hex

REM AXF file
  copy Blinky.elf Blinky.AXF
  pause

REM list file
  arm-none-eabi-objdump -S  Blinky.axf >Blinky.lst
