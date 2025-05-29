import tensorflow as tf
from tensorflow import keras
from keras import layers
from keras.optimizers import Adam
import numpy as np
import os
import json
import pandas as pd
from datetime import datetime
import shutil

class Normalize:
    def __init__(self, data: np.ndarray) -> None:
        self.data: np.ndarray = np.copy(data)
        self.__mean: np.ndarray = data.mean(axis=0)
        self.__std_dev: np.ndarray = data.std(axis=0)
        # Avoid dividing by zero / Избегать деления на ноль
        self.__std_dev[self.__std_dev == 0] = 1.0

    def normalizeData(self) -> np.ndarray:
        return (self.data - self.__mean) / self.__std_dev

    def DeNormalizeData(self, normalized_data: np.ndarray, axes=None) -> np.ndarray:
        if axes is None:
            return normalized_data * self.__std_dev + self.__mean
        else:
            return normalized_data * self.__std_dev[axes] + self.__mean[axes]


def denoise_data(data: np.ndarray, window_size: int) -> np.ndarray:
    return pd.Series(data).rolling(window=window_size).mean().iloc[window_size - 1:].values


def days_since_zero_date(date_input):
    """
    Calculate days from base date 2020-01-01 to input date /
    Рассчитать дни от базовой даты 2020-01-01 до входной даты
    """
    # Check input type / Проверить тип ввода
    if isinstance(date_input, str):
        # Convert string to datetime / Преобразовать строку в datetime
        date_format = "%Y-%m-%d"
        date_obj = datetime.strptime(date_input, date_format)
    else:
        # Use directly if already datetime / Использовать напрямую если уже datetime
        date_obj = date_input

    # Base date 2020-01-01 / Базовая дата
    zero_date = datetime(2020, 1, 1)

    # Calculate days / Рассчитать дни
    delta = date_obj - zero_date
    return delta.days

def load_and_prepare_new_data(city_file, parameter, start_date, end_date):
    """
    Load and prepare new data for fine-tuning /
    Загрузить и подготовить новые данные для тонкой настройки
    """
    # Map parameters from model to new data /
    # Сопоставить параметры модели с новыми данными
    parameter_mapping = {
        "temperature": "temperature_avg",
        "humidity": "humidity_avg",
        "wind": "wind_speed_max"
    }

    # Read CSV file / Прочитать CSV файл
    df = pd.read_csv(city_file)

    # Convert date format / Преобразовать формат даты
    df['date'] = pd.to_datetime(df['date'])

    # Filter by date range / Фильтровать по диапазону дат
    mask = (df['date'] >= start_date) & (df['date'] <= end_date)
    df = df.loc[mask]

    if len(df) == 0:
        print(f"No data available between {start_date} and {end_date}")
        return None, None

    # Map parameter name if needed / Сопоставить имя параметра если нужно
    actual_param = parameter
    if parameter in parameter_mapping:
        actual_param = parameter_mapping[parameter]

    # Check if parameter exists in data / Проверить наличие параметра в данных
    if actual_param not in df.columns:
        print(f"Parameter {actual_param} not found in data")
        return None, None

    # Calculate days from base date / Рассчитать дни от базовой даты
    df['days'] = df['date'].apply(days_since_zero_date)

    # Prepare data / Подготовить данные
    data = df[['days', actual_param]].values

    # Handle NaN values / Обработать NaN значения
    if np.isnan(data).any():
        print(f"Data contains NaN values, filtering out...")
        mask = ~np.isnan(data).any(axis=1)
        data = data[mask]
        dates = df['date'][mask].reset_index(drop=True)
    else:
        dates = df['date'].reset_index(drop=True)

    if len(data) == 0:
        print(f"No data left after filtering NaN values")
        return None, None

    print(f"Loaded {len(data)} rows for {os.path.basename(city_file)} - {parameter}")
    return data, dates

# Custom layer definitions matching original model /
# Определения пользовательских слоев как в исходной модели
class SinLayer(layers.Layer):
    def __init__(self, number_of_sinuses=4, **kwargs):
        super(SinLayer, self).__init__(**kwargs)
        self.number_of_sinuses = number_of_sinuses

    def build(self, input_shape):
        self.kernel = self.add_weight(
            name="kernel",
            shape=(self.number_of_sinuses, 3),
            initializer="random_normal",
            trainable=True
        )
        self.bias = self.add_weight(
            name="bias",
            shape=(),
            initializer="zeros",
            trainable=True
        )
        super(SinLayer, self).build(input_shape)

    def call(self, inputs):
        result = 0
        for i in range(self.number_of_sinuses):
            result += self.kernel[i][0] * tf.sin(
                self.kernel[i][1] * inputs + self.kernel[i][2]
            )
        return result + self.bias

    def get_config(self):
        config = super(SinLayer, self).get_config()
        config.update({"number_of_sinuses": self.number_of_sinuses})
        return config


class DayAdjustmentLayer(tf.keras.layers.Layer):
    def __init__(self, denoised_length, **kwargs):
        super(DayAdjustmentLayer, self).__init__(**kwargs)
        self.denoised_length = tf.constant(denoised_length, dtype=tf.float32)

    def call(self, inputs):
        # Convert relative days to future days /
        # Преобразовать относительные дни в будущие дни
        return inputs + self.denoised_length

    def get_config(self):
        config = super(DayAdjustmentLayer, self).get_config()
        config.update({
            'denoised_length': float(self.denoised_length.numpy())
        })
        return config


class DenormalizeLayer(tf.keras.layers.Layer):
    def __init__(self, mean, std_dev, **kwargs):
        super(DenormalizeLayer, self).__init__(**kwargs)
        self.mean = tf.constant(mean, dtype=tf.float32)
        self.std_dev = tf.constant(std_dev, dtype=tf.float32)

    def call(self, inputs):
        return inputs * self.std_dev + self.mean

    def get_config(self):
        config = super(DenormalizeLayer, self).get_config()
        config.update({
            'mean': float(self.mean.numpy()),
            'std_dev': float(self.std_dev.numpy())
        })
        return config


def load_base_model_weights(model_path):
    """Load weights from saved model file /
    Загрузить веса из сохраненного файла модели"""
    try:
        # For keras model files / Для файлов моделей keras
        if model_path.endswith('.keras') or model_path.endswith('.h5'):
            print(f"Reading weights from {model_path}")
            # Load weights from file / Загрузить веса из файла
            saved_weights = keras.models.load_model(
                model_path,
                custom_objects={
                    'SinLayer': SinLayer,
                    'DayAdjustmentLayer': DayAdjustmentLayer,
                    'DenormalizeLayer': DenormalizeLayer
                },
                compile=False
            ).get_weights()
            return saved_weights
        elif model_path.endswith('.tflite'):
            print(f"Cannot directly read weights from TFLite file: {model_path}")
            return None
        else:
            print(f"Unsupported file format: {model_path}")
            return None
    except Exception as e:
        print(f"Error reading weights: {e}")
        return None


def extract_base_model_weights(model):
    """Extract base_model weights from enhanced_model /
    Извлечь веса base_model из enhanced_model"""
    # Enhanced_model structure: / Структура enhanced_model:
    # Input -> DayAdjustmentLayer -> base_model -> DenormalizeLayer -> Output
    for layer in model.layers:
        if isinstance(layer, keras.Model):  # Find submodel layer (base_model)
            return layer.get_weights()
    return None


def recreate_base_model(number_of_sinuses=4):
    """Recreate original model / Воссоздать исходную модель"""
    inputs = keras.Input(shape=(1,))
    outputs = SinLayer(number_of_sinuses=number_of_sinuses)(inputs)
    model = keras.Model(inputs=inputs, outputs=outputs)
    return model


def fine_tune_model(city_file, parameter, base_model_path, info_path, number_of_sinuses=4):
    """
    Fine-tune model with new data /
    Тонкая настройка модели с новыми данными
    """
    print(f"\nStarting fine-tuning for {os.path.basename(city_file)} - {parameter}...")

    # Read model info / Прочитать информацию модели
    with open(info_path, 'r') as f:
        model_info = json.load(f)

    print(f"Model info: {model_info}")

    # Set date range / Установить диапазон дат
    end_date = datetime(2025, 4, 8)
    start_date = datetime(2025, 3, 8)

    # Load new data / Загрузить новые данные
    new_data, dates = load_and_prepare_new_data(city_file, parameter, start_date, end_date)
    if new_data is None or len(new_data) < 7:
        print(f"Insufficient new data for {os.path.basename(city_file)} - {parameter}")
        return None, None

    print(f"Loaded {len(new_data)} rows of new data")

    # Normalize new data using old parameters /
    # Нормализовать новые данные используя старые параметры
    mean = model_info['mean']
    std_dev = model_info['std_dev']
    denoised_length = model_info['denoised_length']

    normalize_class = Normalize(new_data[:, 1].reshape(-1, 1))
    normalize_class._Normalize__mean = np.array([mean])
    normalize_class._Normalize__std_dev = np.array([std_dev])
    normalized_new_data = normalize_class.normalizeData().flatten()

    # Create training dataset (days -> values) /
    # Создать набор данных для обучения (дни -> значения)
    X = new_data[:, 0].reshape(-1, 1)  # Absolute days / Абсолютные дни
    y = normalized_new_data.reshape(-1, 1)  # Normalized values / Нормализованные значения

    print(f"X shape: {X.shape}, y shape: {y.shape}")

    # Recreate base model with same structure /
    # Воссоздать базовую модель с той же структурой
    base_model = recreate_base_model(number_of_sinuses)

    # Attempt to load weights from saved model /
    # Попытка загрузить веса из сохраненной модели
    try:
        # For enhanced_model path / Для пути enhanced_model
        if 'model_keras' in base_model_path:
            print("Loading enhanced model...")
            with tf.keras.utils.custom_object_scope({
                'SinLayer': SinLayer,
                'DayAdjustmentLayer': DayAdjustmentLayer,
                'DenormalizeLayer': DenormalizeLayer
            }):
                enhanced_model = keras.models.load_model(base_model_path, compile=False)

                # Find base_model within enhanced_model /
                # Найти base_model внутри enhanced_model
                for layer in enhanced_model.layers:
                    if isinstance(layer, keras.Model):
                        base_model_weights = layer.get_weights()
                        print(f"Found base_model in enhanced_model, weight shapes: {[w.shape for w in base_model_weights]}")
                        base_model.set_weights(base_model_weights)
                        break
        else:
            # Handle TFLite differently / Обработать TFLite по-другому
            print("Cannot load weights from TFLite, using random weights")

    except Exception as e:
        print(f"Error: {e}")

    # Compile model with low learning rate for fine-tuning /
    # Компилировать модель с низкой скоростью обучения для тонкой настройки
    base_model.compile(
        optimizer=Adam(learning_rate=0.0005, beta_1=0.9, beta_2=0.999),
        loss='mse',
        metrics=['mae']
    )

    # Fine-tuning / Тонкая настройка
    print("Starting fine-tuning...")
    history = base_model.fit(
        X - denoised_length,  # Adjust X to relative days / Преобразовать X в относительные дни
        y,
        epochs=50,
        batch_size=min(16, len(X) // 2),
        validation_split=0.2,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor='val_loss',
                patience=10,
                restore_best_weights=True
            )
        ],
        verbose=1
    )

    print(f"Fine-tuning completed for {os.path.basename(city_file)} - {parameter}")

    # Create new enhanced model with custom layers /
    # Создать новую улучшенную модель с пользовательскими слоями
    print(f"Creating new enhanced model...")

    # Manually create integrated model / Вручную создать интегрированную модель
    input_layer = keras.Input(shape=(1,))
    adjusted_day = DayAdjustmentLayer(denoised_length)(input_layer)
    prediction = base_model(adjusted_day)
    denormalized = DenormalizeLayer(mean, std_dev)(prediction)
    enhanced_model = keras.Model(inputs=input_layer, outputs=denormalized)

    # Update model info / Обновить информацию модели
    new_model_info = {
        'mean': float(mean),
        'std_dev': float(std_dev),
        'denoised_length': int(denoised_length),
        'city': os.path.basename(city_file).replace('.csv', ''),
        'parameter': parameter,
        'updated_date': datetime.now().strftime('%Y-%m-%d')
    }

    return enhanced_model, new_model_info


def update_models():
    """
    Update all models / Обновить все модели
    """
    model_dir = 'modelzz'  # Directory for TFLite models / Директория для моделей TFLite
    info_dir = 'model_info'  # Directory for model info / Директория для информации о моделях
    keras_dir = 'model_keras'  # Directory for Keras models / Директория для моделей Keras
    data_dir = 'cities'  # Directory for city data / Директория для данных городов

    # Create directories for new models / Создать директории для новых моделей
    new_model_dir = 'model_updated'
    new_info_dir = 'model_info_updated'
    new_keras_dir = 'model_keras_updated'

    os.makedirs(new_model_dir, exist_ok=True)
    os.makedirs(new_info_dir, exist_ok=True)
    os.makedirs(new_keras_dir, exist_ok=True)

    # Iterate through all models / Перебрать все модели
    updated_models = []

    # Prioritize Keras models if available / Отдать приоритет моделям Keras если доступны
    if os.path.exists(keras_dir):
        print(f"Found Keras model directory: {keras_dir}")

        for model_file in os.listdir(keras_dir):
            if model_file.endswith('.keras'):
                city_param = model_file.replace('.keras', '')
                info_file = f'{city_param}_info.json'

                # Full paths / Полные пути
                model_path = os.path.join(keras_dir, model_file)
                info_path = os.path.join(info_dir, info_file)

                if not os.path.exists(info_path):
                    print(f"Info file {info_path} not found, skipping model")
                    continue

                # Extract city name and parameter / Извлечь название города и параметр
                parts = city_param.split('_')
                if len(parts) < 2:
                    print(f"Invalid file name: {model_file}")
                    continue

                city_name = parts[0]
                parameter = parts[1]

                print(f"Updating Keras model for {city_name} - {parameter}")

                # Fine-tune model / Тонкая настройка модели
                city_file = f'{data_dir}/{city_name}.csv'
                if not os.path.exists(city_file):
                    print(f"Data file {city_file} not found")
                    continue

                updated_model, new_info = fine_tune_model(
                    city_file,
                    parameter,
                    model_path,
                    info_path,
                    number_of_sinuses=4  # Number of sines in original model /
                )

                if updated_model is not None:
                    # Save new model / Сохранить новую модель
                    new_model_path = os.path.join(new_keras_dir, model_file)
                    new_info_path = os.path.join(new_info_dir, info_file)
                    new_tflite_path = os.path.join(new_model_dir, model_file.replace('.keras', '.tflite'))

                    # Save new Keras model / Сохранить новую модель Keras
                    updated_model.save(new_model_path)
                    print(f"Saved new Keras model at {new_model_path}")

                    # Save new model info / Сохранить новую информацию модели
                    with open(new_info_path, 'w') as f:
                        json.dump(new_info, f)
                    print(f"Saved new model info at {new_info_path}")

                    # Convert and save TFLite model / Конвертировать и сохранить модель TFLite
                    converter = tf.lite.TFLiteConverter.from_keras_model(updated_model)
                    tflite_model = converter.convert()

                    with open(new_tflite_path, 'wb') as f:
                        f.write(tflite_model)
                    print(f"Saved new TFLite model at {new_tflite_path}")

                    updated_models.append(f"{city_name}_{parameter}")
    else:
        print("Keras model directory not found")

    # Package updated models / Упаковать обновленные модели
    if updated_models:
        print(f"Successfully updated {len(updated_models)} models:")
        for model in updated_models:
            print(f"  - {model}")

        # Create zip files / Создать zip архивы
        shutil.make_archive('model_updated', 'zip', new_model_dir)
        shutil.make_archive('model_info_updated', 'zip', new_info_dir)
        shutil.make_archive('model_keras_updated', 'zip', new_keras_dir)

        print("Created zip files for updated models")
    else:
        print("No models were updated")


if __name__ == "__main__":
    update_models()