- It can be quite triky when 
	1. your function has multiple exit points and you need to do some cleanup work at all exit points; 
	2. your function needs to release some resouces but these are allocated in another function; 
	3. you do not git commit frequently. 
	It is easy to forget to initilize the resouce in some paths for another funciton or forget to release it for some exit points of your function
- links about using goto for multiple exit points https://docs.kernel.org/process/coding-style.html#centralized-exiting-of-functions (like the err_foo_bar case suggests, sometimes we can not avoid multiple exit points just by using one if-else otherwise the code is nested) https://eli.thegreenplace.net/2009/04/27/using-goto-for-error-handling-in-c  https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/recommendations/memory-management-mem/mem12-c/
- links about allocating & deallocating style https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/recommendations/memory-management-mem/mem00-c/ (who should manage the lifetime of the allocated object is important)  https://docs.kernel.org/core-api/kref.html