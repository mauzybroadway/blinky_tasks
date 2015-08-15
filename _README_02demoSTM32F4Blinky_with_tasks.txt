_README_02demoSTM32F4Blinky_with_tasks.txt wmh 2015-04-28

 Demonstrate tasking with two tasks, main() and Task1
  - main() -- polls switches, cycles LEDs using msTicks delays
  - Task1 -- increments msTicks
  - uses PendSV to switch tasks
  - uses SVC #0 to set PendSV
  - calls SVC #0 in SysTick interrupt to switch tasks
  - calls SVC #0 in Task1 to suspend Task1
 
 other information:
   - uses SVC #1 to install Task1.  Number of tasks is hardcoded and needs to be generalized to install any task.
   - PendSV (the tasker) is hardcoded to two tasks only and needs to be generalized
   - the use of SysTick to call SVC #0 to set PendSV is purely for the (worst case) demo; setting PendSV anywhere either directly or through SVC #0 is all that is required to switch tasks
  
 
bugs:
  - main is using non-existent addresses to access msTicks and its other data.