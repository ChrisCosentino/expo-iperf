#include "iperf_config.h"

#if defined(HAVE_PTHREAD) || defined(__APPLE__) || defined(__ANDROID__)
#include <pthread.h>
#endif

#if defined(__ANDROID__)

/* Adding missing `pthread` related definitions in Android.
 */

#define PTHREAD_CANCEL_ASYNCHRONOUS 0
#define PTHREAD_CANCEL_ENABLE 0

int pthread_setcanceltype(int type, int *oldtype);
int pthread_setcancelstate(int state, int *oldstate);
int pthread_cancel(pthread_t thread_id);

#endif // defined(__ANDROID__)


