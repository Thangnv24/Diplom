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
        # Avoid dividing by zero
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
    Tính số ngày kể từ ngày 2020-01-01 đến ngày đầu vào
    Đầu vào có thể là chuỗi hoặc đối tượng datetime/Timestamp
    """
    # Kiểm tra kiểu đầu vào
    if isinstance(date_input, str):
        # Nếu là chuỗi, chuyển thành datetime
        date_format = "%Y-%m-%d"
        date_obj = datetime.strptime(date_input, date_format)
    else:
        # Nếu đã là datetime hoặc Timestamp, sử dụng trực tiếp
        date_obj = date_input

    # Ngày cơ sở 2020-01-01
    zero_date = datetime(2020, 1, 1)

    # Tính số ngày
    delta = date_obj - zero_date
    return delta.days


def load_and_prepare_new_data(city_file, parameter, start_date, end_date):
    """
    Tải và chuẩn bị dữ liệu mới cho fine-tuning
    """
    # Map thông số từ mô hình sang dữ liệu mới
    parameter_mapping = {
        "temperature": "temperature_avg",
        "humidity": "humidity_avg",
        "wind": "wind_speed_max"
    }

    # Đọc file CSV
    df = pd.read_csv(city_file)

    # Chuyển đổi định dạng ngày
    df['date'] = pd.to_datetime(df['date'])

    # Lọc theo khoảng thời gian
    mask = (df['date'] >= start_date) & (df['date'] <= end_date)
    df = df.loc[mask]

    if len(df) == 0:
        print(f"Không có dữ liệu trong khoảng {start_date} đến {end_date}")
        return None, None

    # Ánh xạ tên tham số nếu cần
    actual_param = parameter
    if parameter in parameter_mapping:
        actual_param = parameter_mapping[parameter]

    # Kiểm tra tham số có tồn tại trong dữ liệu không
    if actual_param not in df.columns:
        print(f"Tham số {actual_param} không có trong dữ liệu")
        return None, None

    # Tính số ngày kể từ ngày cơ sở
    df['days'] = df['date'].apply(days_since_zero_date)

    # Chuẩn bị dữ liệu
    data = df[['days', actual_param]].values

    # Kiểm tra và xử lý dữ liệu NaN
    if np.isnan(data).any():
        print(f"Dữ liệu chứa giá trị NaN, đang lọc bỏ...")
        mask = ~np.isnan(data).any(axis=1)
        data = data[mask]
        dates = df['date'][mask].reset_index(drop=True)
    else:
        dates = df['date'].reset_index(drop=True)

    if len(data) == 0:
        print(f"Không còn dữ liệu sau khi lọc bỏ giá trị NaN")
        return None, None

    print(f"Đã tải {len(data)} dòng dữ liệu cho {os.path.basename(city_file)} - {parameter}")
    return data, dates

# Định nghĩa lại các lớp tùy chỉnh giống hệt như trong mô hình gốc
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
        # Chuyển đổi ngày tương đối (0, 1, 2...) thành ngày tương lai
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
    """Tải trọng số từ tệp model đã lưu"""
    try:
        # Nếu model là file keras, đọc trọng số
        if model_path.endswith('.keras') or model_path.endswith('.h5'):
            print(f"Đang đọc trọng số từ {model_path}")
            # Đọc trọng số từ file
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
            print(f"Không thể trực tiếp đọc trọng số từ file TFLite: {model_path}")
            return None
        else:
            print(f"Không hỗ trợ định dạng file: {model_path}")
            return None
    except Exception as e:
        print(f"Lỗi khi đọc trọng số: {e}")
        return None


def extract_base_model_weights(model):
    """Trích xuất trọng số của base_model từ enhanced_model"""
    # Giả sử enhanced_model có cấu trúc:
    # Input -> DayAdjustmentLayer -> base_model -> DenormalizeLayer -> Output
    for layer in model.layers:
        if isinstance(layer, keras.Model):  # Tìm layer là model con (base_model)
            return layer.get_weights()
    return None


def recreate_base_model(number_of_sinuses=4):
    """Tạo lại mô hình gốc"""
    inputs = keras.Input(shape=(1,))
    outputs = SinLayer(number_of_sinuses=number_of_sinuses)(inputs)
    model = keras.Model(inputs=inputs, outputs=outputs)
    return model


def fine_tune_model(city_file, parameter, base_model_path, info_path, number_of_sinuses=4):
    """
    Fine-tune mô hình với dữ liệu mới
    """
    print(f"\nĐang bắt đầu fine-tune cho {os.path.basename(city_file)} - {parameter}...")

    # Đọc thông tin model cũ
    with open(info_path, 'r') as f:
        model_info = json.load(f)

    print(f"Thông tin model: {model_info}")

    # Đọc dữ liệu mới
    end_date = datetime(2025, 4, 8)
    start_date = datetime(2025, 3, 8)

    # Tải dữ liệu mới
    new_data, dates = load_and_prepare_new_data(city_file, parameter, start_date, end_date)
    if new_data is None or len(new_data) < 7:
        print(f"Không đủ dữ liệu mới cho {os.path.basename(city_file)} - {parameter}")
        return None, None

    print(f"Đã tải {len(new_data)} dòng dữ liệu mới")

    # Chuẩn hóa dữ liệu mới sử dụng thông số cũ
    mean = model_info['mean']
    std_dev = model_info['std_dev']
    denoised_length = model_info['denoised_length']

    normalize_class = Normalize(new_data[:, 1].reshape(-1, 1))
    normalize_class._Normalize__mean = np.array([mean])
    normalize_class._Normalize__std_dev = np.array([std_dev])
    normalized_new_data = normalize_class.normalizeData().flatten()

    # Tạo tập dữ liệu huấn luyện (days -> values)
    X = new_data[:, 0].reshape(-1, 1)  # Ngày tuyệt đối
    y = normalized_new_data.reshape(-1, 1)  # Giá trị đã chuẩn hóa

    print(f"X shape: {X.shape}, y shape: {y.shape}")

    # Tạo lại mô hình cơ bản (base_model) với cùng cấu trúc
    base_model = recreate_base_model(number_of_sinuses)

    # Cố gắng tải trọng số từ mô hình đã lưu
    try:
        # Nếu base_model_path là đường dẫn đến enhanced_model
        if 'model_keras' in base_model_path:
            print("Đang tải mô hình enhanced...")
            with tf.keras.utils.custom_object_scope({
                'SinLayer': SinLayer,
                'DayAdjustmentLayer': DayAdjustmentLayer,
                'DenormalizeLayer': DenormalizeLayer
            }):
                enhanced_model = keras.models.load_model(base_model_path, compile=False)

                # Tìm base_model bên trong enhanced_model
                for layer in enhanced_model.layers:
                    if isinstance(layer, keras.Model):
                        base_model_weights = layer.get_weights()
                        print(
                            f"Đã tìm thấy base_model trong enhanced_model, shape trọng số: {[w.shape for w in base_model_weights]}")
                        base_model.set_weights(base_model_weights)
                        break
        else:
            # Nếu là TFLite, cần xử lý khác
            print("Không thể tải trọng số từ TFLite, sử dụng trọng số ngẫu nhiên")

    except Exception as e:
        print(f"Lỗi khi tải trọng số: {e}")
        print("Sử dụng trọng số ngẫu nhiên")

    # Compile model với learning rate thấp để fine-tuning
    base_model.compile(
        optimizer=Adam(learning_rate=0.0005, beta_1=0.9, beta_2=0.999),
        loss='mse',
        metrics=['mae']
    )

    # Fine-tuning
    print("Bắt đầu fine-tuning...")
    history = base_model.fit(
        X - denoised_length,  # Điều chỉnh X thành ngày tương đối
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

    print(f"Fine-tuning hoàn tất cho {os.path.basename(city_file)} - {parameter}")

    # Tạo enhanced model mới với các lớp custom
    print(f"Đang tạo enhanced model mới...")

    # Tạo model tích hợp thủ công
    input_layer = keras.Input(shape=(1,))
    adjusted_day = DayAdjustmentLayer(denoised_length)(input_layer)
    prediction = base_model(adjusted_day)
    denormalized = DenormalizeLayer(mean, std_dev)(prediction)
    enhanced_model = keras.Model(inputs=input_layer, outputs=denormalized)

    # Cập nhật thông tin mô hình
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
    Cập nhật tất cả các model
    """
    model_dir = 'modelzz'  # Thư mục chứa model TFLite
    info_dir = 'model_info'  # Thư mục chứa thông tin model
    keras_dir = 'model_keras'  # Thư mục chứa model Keras
    data_dir = 'cities'  # Thư mục chứa dữ liệu thành phố

    # Tạo thư mục cho models mới
    new_model_dir = 'model_updated'
    new_info_dir = 'model_info_updated'
    new_keras_dir = 'model_keras_updated'

    os.makedirs(new_model_dir, exist_ok=True)
    os.makedirs(new_info_dir, exist_ok=True)
    os.makedirs(new_keras_dir, exist_ok=True)

    # Lặp qua tất cả các model
    updated_models = []

    # Ưu tiên sử dụng model Keras nếu có
    if os.path.exists(keras_dir):
        print(f"Đã tìm thấy thư mục model Keras: {keras_dir}")

        for model_file in os.listdir(keras_dir):
            if model_file.endswith('.keras'):
                city_param = model_file.replace('.keras', '')
                info_file = f'{city_param}_info.json'

                # Đường dẫn đầy đủ
                model_path = os.path.join(keras_dir, model_file)
                info_path = os.path.join(info_dir, info_file)

                if not os.path.exists(info_path):
                    print(f"Không tìm thấy file thông tin {info_path}, bỏ qua model")
                    continue

                # Tách tên thành phố và tham số
                parts = city_param.split('_')
                if len(parts) < 2:
                    print(f"Tên file không hợp lệ: {model_file}")
                    continue

                city_name = parts[0]
                parameter = parts[1]

                print(f"Đang cập nhật model Keras cho {city_name} - {parameter}")

                # Fine-tune model
                city_file = f'{data_dir}/{city_name}.csv'
                if not os.path.exists(city_file):
                    print(f"Không tìm thấy file dữ liệu {city_file}")
                    continue

                updated_model, new_info = fine_tune_model(
                    city_file,
                    parameter,
                    model_path,
                    info_path,
                    number_of_sinuses=4  # Số lượng sin trong mô hình gốc
                )

                if updated_model is not None:
                    # Lưu model mới
                    new_model_path = os.path.join(new_keras_dir, model_file)
                    new_info_path = os.path.join(new_info_dir, info_file)
                    new_tflite_path = os.path.join(new_model_dir, model_file.replace('.keras', '.tflite'))

                    # Lưu model Keras mới
                    updated_model.save(new_model_path)
                    print(f"Đã lưu model Keras mới tại {new_model_path}")

                    # Lưu thông tin model mới
                    with open(new_info_path, 'w') as f:
                        json.dump(new_info, f)
                    print(f"Đã lưu thông tin model mới tại {new_info_path}")

                    # Chuyển đổi và lưu model mới dạng TFLite
                    converter = tf.lite.TFLiteConverter.from_keras_model(updated_model)
                    tflite_model = converter.convert()

                    with open(new_tflite_path, 'wb') as f:
                        f.write(tflite_model)
                    print(f"Đã lưu model TFLite mới tại {new_tflite_path}")

                    updated_models.append(f"{city_name}_{parameter}")
    else:
        print("Không tìm thấy thư mục model Keras")

    # Đóng gói các model đã cập nhật
    if updated_models:
        print(f"Đã cập nhật thành công {len(updated_models)} model:")
        for model in updated_models:
            print(f"  - {model}")

        # Tạo các file zip
        shutil.make_archive('model_updated', 'zip', new_model_dir)
        shutil.make_archive('model_info_updated', 'zip', new_info_dir)
        shutil.make_archive('model_keras_updated', 'zip', new_keras_dir)

        print("Đã tạo các file zip cho model đã cập nhật")
    else:
        print("Không có model nào được cập nhật")


# Chạy cập nhật
if __name__ == "__main__":
    update_models()