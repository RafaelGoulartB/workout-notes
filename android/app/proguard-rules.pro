# ML Kit discovers these component registrars by class name from manifest
# metadata. R8 otherwise removes their no-argument constructors in release
# builds, making BarcodeScanning.getClient() fail with a NullPointerException.
-keep class com.google.mlkit.vision.barcode.internal.BarcodeRegistrar {
    public <init>();
}
-keep class com.google.mlkit.vision.common.internal.VisionCommonRegistrar {
    public <init>();
}
-keep class com.google.mlkit.common.internal.CommonComponentRegistrar {
    public <init>();
}
