public let stableAeroSpaceAppId: String = "com.github.shermantsang.airspace"
#if DEBUG
    public let aeroSpaceAppId: String = "com.github.shermantsang.airspace.debug"
    public let aeroSpaceAppName: String = "AirSpace-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "AirSpace"
#endif
