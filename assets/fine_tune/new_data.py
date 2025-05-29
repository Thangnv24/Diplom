import requests
import pandas as pd
import time
from datetime import datetime
import json

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

with open('city_coords.json', 'r') as f:
    city_coords = json.load(f)

for city in city_coords:
    latitude, longitude = city_coords[city]
    weather_data = get_weather_history(latitude, longitude)
    print(f"{city}: Latitude: {latitude}, Longitude: {longitude}")
    time.sleep(0.2)
    weather_data.to_csv(f"cities/{city}.csv", index=False)

