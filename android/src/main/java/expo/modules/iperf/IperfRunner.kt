//package expo.modules.iperf
//
//class IperfRunner {
package expo.modules.iperf

class IperfRunner private constructor() {

    companion object {
        @Volatile
        private var instance: IperfRunner? = null

        fun getInstance(): IperfRunner {
            return instance ?: synchronized(this) {
                instance ?: IperfRunner().also { instance = it }
            }
        }

        init {
            System.loadLibrary("iperf3")
        }
    }

    interface LogCallback {
        fun onLog(line: String)
    }

    private var logCallback: LogCallback? = null

    fun start(port: Int, json: Boolean, udp: Boolean, callback: LogCallback) {
        logCallback = callback
        nativeStart(port, json, udp, callback)
    }

    fun stop() {
        nativeStop()
        logCallback = null
    }

    fun isRunning(): Boolean {
        return nativeIsRunning()
    }

    // Native methods (implemented in JNI)
    private external fun nativeStart(port: Int, json: Boolean, udp: Boolean, callback: LogCallback)
    private external fun nativeStop()
    private external fun nativeIsRunning(): Boolean
}