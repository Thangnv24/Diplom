import requests
import pandas as pd
import time
from datetime import datetime


def get_weather_history(lat, lon, start_year=2025, end_year=2025):
    base_url = "https://archive-api.open-meteo.com/v1/archive"

    today = f"2025-04-08" #datetime.today().strftime("%Y-%m-%d")
    dfs = []

    for year in range(start_year, end_year + 1):
        end_date = f"{year}-12-31"
        if year == end_year:
            end_date = today

        params = {
            "latitude": lat,
            "longitude": lon,
            "start_date": f"2025-03-08",
            "end_date": end_date,
            "daily": ["temperature_2m_mean", "relative_humidity_2m_mean", "wind_speed_10m_max"],
            "timezone": "auto"
        }
        response = requests.get(base_url, params=params)

        if response.status_code == 200:
            data = response.json()
            df = pd.DataFrame({
                "date": data["daily"]["time"],
                "temperature_avg": data["daily"]["temperature_2m_mean"],
                "humidity_avg": data["daily"]["relative_humidity_2m_mean"],
                "wind_speed_max": data["daily"]["wind_speed_10m_max"]
            })
            dfs.append(df)
        else:
            print(f"Error for {year}: {response.status_code}")

    # Gộp tất cả dữ liệu lại thành một DataFrame
    weather_df = pd.concat(dfs, ignore_index=True)
    return weather_df

city_coords = {
    "Hanoi": (21.0285, 105.8544),
    "Moscow": (55.7558, 37.6173),
    "Saint Petersburg": (59.9343, 30.3351),
    "Paris": (48.8566, 2.3522),
    "London": (51.5074, -0.1278),
    "New York": (40.7128, -74.0060),
    "Beijing": (39.9042, 116.4074),
    "Rome": (41.9028, 12.4964),
    "Tokyo": (35.6895, 139.6917),
    "Shanghai": (31.2304, 121.4737),
    "Los Angeles": (34.0522, -118.2437),
    "Dubai": (25.276987, 55.296249),
    "Mumbai": (19.0760, 72.8777),
    "Ho Chi Minh City": (10.8231, 106.6297),
    "Berlin": (52.5200, 13.4050),
    "Sydney": (-33.8688, 151.2093),
    "Cairo": (30.0444, 31.2357),
    "Toronto": (43.6532, -79.3832),
    "Seoul": (37.5665, 126.9780),
    "Singapore": (1.3521, 103.8198)
}

for city in city_coords:
    latitude, longitude = city_coords[city]
    weather_data = get_weather_history(latitude, longitude)
    print(f"{city}: Latitude: {latitude}, Longitude: {longitude}")
    time.sleep(0.2)
    weather_data.to_csv(f"cities/{city}.csv", index=False)

