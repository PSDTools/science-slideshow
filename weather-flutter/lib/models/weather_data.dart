/// Weather data model matching the weather.com PWS API response shape.
class ImperialData {
  final double? temp;
  final double? windSpeed;
  final double? windGust;
  final double? windChill;
  final double? heatIndex;
  final double? precipRate;
  final double? pressure;
  final double? dewpt;
  final double? elev;

  const ImperialData({
    this.temp,
    this.windSpeed,
    this.windGust,
    this.windChill,
    this.heatIndex,
    this.precipRate,
    this.pressure,
    this.dewpt,
    this.elev,
  });

  factory ImperialData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ImperialData();
    return ImperialData(
      temp: (json['temp'] as num?)?.toDouble(),
      windSpeed: (json['windSpeed'] as num?)?.toDouble(),
      windGust: (json['windGust'] as num?)?.toDouble(),
      windChill: (json['windChill'] as num?)?.toDouble(),
      heatIndex: (json['heatIndex'] as num?)?.toDouble(),
      precipRate: (json['precipRate'] as num?)?.toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble(),
      dewpt: (json['dewpt'] as num?)?.toDouble(),
      elev: (json['elev'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (temp != null) 'temp': temp,
        if (windSpeed != null) 'windSpeed': windSpeed,
        if (windGust != null) 'windGust': windGust,
        if (windChill != null) 'windChill': windChill,
        if (heatIndex != null) 'heatIndex': heatIndex,
        if (precipRate != null) 'precipRate': precipRate,
        if (pressure != null) 'pressure': pressure,
        if (dewpt != null) 'dewpt': dewpt,
        if (elev != null) 'elev': elev,
      };
}

class WeatherData {
  final ImperialData imperial;
  final double? humidity;
  final double? uv;
  final double? winddir;
  final String? stationID;
  final String? neighborhood;
  final String? country;
  final String? obsTimeLocal;
  final double? lat;
  final double? lon;

  const WeatherData({
    this.imperial = const ImperialData(),
    this.humidity,
    this.uv,
    this.winddir,
    this.stationID,
    this.neighborhood,
    this.country,
    this.obsTimeLocal,
    this.lat,
    this.lon,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      imperial: ImperialData.fromJson(json['imperial'] as Map<String, dynamic>?),
      humidity: (json['humidity'] as num?)?.toDouble(),
      uv: (json['uv'] as num?)?.toDouble(),
      winddir: (json['winddir'] as num?)?.toDouble(),
      stationID: json['stationID'] as String?,
      neighborhood: json['neighborhood'] as String?,
      country: json['country'] as String?,
      obsTimeLocal: json['obsTimeLocal'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'imperial': imperial.toJson(),
        if (humidity != null) 'humidity': humidity,
        if (uv != null) 'uv': uv,
        if (winddir != null) 'winddir': winddir,
        if (stationID != null) 'stationID': stationID,
        if (neighborhood != null) 'neighborhood': neighborhood,
        if (country != null) 'country': country,
        if (obsTimeLocal != null) 'obsTimeLocal': obsTimeLocal,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
      };
}
