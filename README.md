# Название проекта

**Прогноз погоды на основе машинного обучения и приложение Flutter**

---

## Цели проекта 

* **ML-модель прогнозирования погоды**: создание и обучение синусоидальной модели с оптимизацией через ADAM и тонкой настройкой для предсказания температуры, влажности и ветра.

* **Мобильное приложение на Flutter**: отображение 7-дневного прогноза для выбранного или ближайшего города с использованием TFLite-моделей.

---

## Структура проекта 

```

assets/
    model.ipynb
    get_data.py
    city_coords.json
    fine_tune/
        new_data.py
        fine_tune.py
        model_keras/                # Сохранённые .keras и .tflite модели по городам и параметрам
        model_info/           # Метаданные для тонкой настройки

lib/
    forecast_screen.dart
    prediction_service.dart
    city_list_screen.dart
    main.dart
android/, ios/, pubspec.yaml
README.md
```

---

## Детали файлов 

### assets/get_data.py:

* Сбор исторических данных через Open-Meteo API (2020–2025) по коорд.: latitude, longitude.

* Формирует CSV с полями: `date`, `temperature_avg`, `humidity_avg`, `wind_speed_max`.

### assets/model.ipynb

* Скрипт для обучения моделей для всех атрибутов и городов, заботится об обучении/правильном сохранении структуры модели, проверяет, тестирует.

### assets/fine_tune/fine\_tune.py

* Логика тонкой настройки модели SinLayer на новых данных (последние 30 дней).
* Создание слоёв DayAdjustment и Denormalize, экспорт в Keras/TFLite.

### assets/city\_coords.json

* JSON-словарь городов с координатами для поиска ближайшего: `{"Hanoi": [21.0285, 105.8544], ...}`.

### assets/fine_tune/model_keras/

* Хранятся сгенерированные модели `.keras` и экспортированные `.tflite` для каждого города и параметра.

### assets/fine_tune/model\_info/

* Метаданные моделей: среднее, std\_dev, denoised\_length, время обновления.

### lib/forecast_screen.dart

* Класс `WeatherForecast` для хранения и визуализации прогноза (3 графика).

### lib/prediction\_service.dart

* Загрузка TFLite-моделей по названию города и параметру, вычисление смещения дней, формирование прогноза на 7 дней.

### lib/city\_list\_screen.dart

* Отображение списка городов, поиск, определение ближайшего через Geolocator и формула гаверсина.

### assets/modelzz/

* Папка с предобученными `.tflite` файлами названных `City_parameter.tflite`.

### Остальное

* `android/`, `ios/`: стандартные каталоги Flutter.
* `pubspec.yaml`: зависимости: `tflite_flutter`, `geolocator`, `fl_chart`, `path_provider`, `intl`.

---

## Как запустить приложение 

1. Установить Python 3.8+, TensorFlow 2.10+.

2. В `backend` выполнить:

   ```bash
   python assets/get_data.py        # сбор данных
   jupyter notebook assets/model.ipynb  # предобработка и обучение
   python assets/fine_tune.py       # тонкая настройка и экспорт
   ```

3. Установить Flutter SDK ≥ 3.x, Dart ≥ 2.12.

4. В `frontend` выполнить:

   ```bash
   flutter pub get
   flutter run                      # запустит на подключённом устройстве/эмуляторе
   ```

## Требования 

* **Python** ≥ 3.8

* **TensorFlow** ≥ 2.10

* **Jupyter Notebook**

* **Flutter** ≥ 3.x, **Dart** ≥ 2.12

* **Пакеты Python**: `requests`, `pandas`, `numpy`, `tensorflow`

* **Пакеты Flutter**: `tflite_flutter`, `geolocator`, `fl_chart`, `path_provider`, `intl`

* **Python** ≥ 3.8

* **TensorFlow** ≥ 2.10

* **Jupyter Notebook**

* **Flutter** ≥ 3.x, **Dart** ≥ 2.12

* **Thư viện Python**: `requests`, `pandas`, `numpy`, `tensorflow`

* **Thư viện Flutter**: `tflite_flutter`, `geolocator`, `fl_chart`, `path_provider`, `intl`


## Результат
* Главная страница приложения, включая поиск и местоположение:

![image](https://github.com/user-attachments/assets/ba37bbba-1cf3-4676-a085-58319e2f01dd)

* Графики и прогнозы:

![image](https://github.com/user-attachments/assets/547ad14e-e5c7-4b58-b9d5-ce9f25e742b4)
![image](https://github.com/user-attachments/assets/a52f4656-7e2e-41a9-8d7f-b6090c743621)
