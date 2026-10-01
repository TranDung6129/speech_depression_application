# Nhật ký giọng nói — app bệnh nhân (WP2)

Bản demo Flutter cho luồng bệnh nhân của dự án *Scoring Depression from Speech Signals*.
Dashboard bác sĩ nằm ở phía web, dùng chung backend JSON API với app này.

## Chạy thử

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` là địa chỉ máy host nhìn từ Android emulator. Máy thật cần địa chỉ
LAN hoặc domain. Backend phải đang chạy — xem `../backend/README.md`.

Yêu cầu Flutter SDK ≥ 3.19 (Dart ≥ 3.3).

## Quyền cần khai báo

**Android** — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

Đặt `minSdkVersion 23` trong `android/app/build.gradle`.

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Ứng dụng cần micro để ghi lại nhật ký giọng nói của bạn.</string>
```

## Cấu trúc

```
lib/
├── main.dart                     điểm vào
├── theme/app_theme.dart          bảng màu
├── models/models.dart            phần A/B/C, cờ chất lượng, phiên cục bộ
├── config.dart                   base URL, phiên bản app, tham số thử lại
├── services/
│   ├── session_config.dart       GET /v1/config: ngưỡng, văn bản B, lời nhắc C
│   ├── recorder_service.dart     thu 16 kHz mono WAV thô + đếm tiếng nói realtime
│   ├── audio_metrics.dart        đo chất lượng trên file (cùng định nghĩa với server)
│   ├── quality_gate.dart         cổng chất lượng trên máy (mục 6)
│   ├── device_context.dart       nguồn micro không xử lý, device_id, thông tin máy
│   ├── session_metadata.dart     metadata mục 5.1 cho ba file
│   ├── storage_service.dart      danh sách phiên cục bộ, cài đặt
│   ├── auth_service.dart         token trong secure storage
│   └── upload_queue.dart         hàng đợi tải phiên lên, bền qua khởi động lại
├── widgets/recording_visuals.dart waveform, lịch
└── screens/
    ├── sign_in_screen.dart       đăng nhập / tạo tài khoản
    ├── home_screen.dart          trang chủ: số phiên, chất lượng phiên vừa rồi, hỗ trợ
    ├── session_screen.dart       một phiên A → B → C
    ├── history_screen.dart       lịch sử và lịch tháng
    └── profile_screen.dart       hồ sơ và cài đặt
```

## Phiên thu (đặc tả WP2 bản 2)

Mỗi phiên là **ba file** cùng `session_id`, phân biệt bằng `task_part`, gửi
một lần tới `POST /v1/sessions`:

| Phần | Nội dung | Thời lượng |
|---|---|---|
| A | im lặng, đo nền nhiễu | 5 giây (tự kết thúc) |
| B | đọc văn bản cố định `text_id` | ~25 giây tiếng nói |
| C | nói tự do theo lời nhắc `prompt_id`, xoay vòng mỗi ngày | ≥ 25 giây tiếng nói |

Ngưỡng tiếng nói thật của cả phiên (`min_speech_sec`, hiện 45 giây, chờ PI
chốt 45 hay 55), văn bản B, danh sách lời nhắc C và ngưỡng cổng chất lượng
**đều do server giữ**, app đọc qua `GET /v1/config` lúc bắt đầu phiên. Đổi
ngưỡng không cần phát hành app mới.

Nút hoàn tất chỉ bật khi phần C đủ `part_c_min_speech_sec` **và** B + C đủ
`min_speech_sec`. Người dùng dừng sớm (nút ✕ trong phần B hoặc C) thì phiên
vẫn được lưu kèm cờ `stopped_early`; phần chưa kịp thu thành file WAV rỗng để
phiên luôn đủ ba file. Thoát trong phần A thì bỏ phiên — chưa có gì để đo.

## Những quyết định đã mã hoá trong code

Các điểm dưới đây ảnh hưởng trực tiếp đến chất lượng dữ liệu, nên đừng sửa nếu
chưa cân nhắc kỹ.

**App thu sạch, server xử lý.** App không chạy phép xử lý tín hiệu nào lên
âm thanh: `echoCancel`, `noiseSuppress`, `autoGain` đều `false`, không lọc,
không chuẩn mức. Lọc thông cao 60 Hz và chuẩn mức −26 dBFS chạy ở server,
trên bản sao, có số phiên bản.

**Nguồn micro không qua xử lý của hệ điều hành (mục 4.2).** Tắt DSP trong app
chưa đủ, vì hệ điều hành có thể tự khử nhiễu và AGC trước khi app nhận mẫu.
`device_context.dart` hỏi code native qua kênh `voice_journal/audio`:

- **Android** (`MainActivity.kt`): `AudioSource.UNPROCESSED` nếu
  `AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED` báo hỗ trợ, không
  thì `VOICE_RECOGNITION`. Plugin `record` 5.2 nhận nguồn này qua
  `AndroidRecordConfig.audioSource`, không cần platform channel thu âm riêng.
- **iOS**: repo chưa có thư mục `ios/`. Khi tạo, thêm vào `AppDelegate.swift`
  một handler cho cùng kênh, đặt `AVAudioSession` ở mode `.measurement`:

  ```swift
  let channel = FlutterMethodChannel(name: "voice_journal/audio",
                                     binaryMessenger: controller.binaryMessenger)
  channel.setMethodCallHandler { call, result in
    switch call.method {
    case "configureMeasurementSession":
      do {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.record, mode: .measurement, options: [])
        try s.setPreferredSampleRate(16000)
        try s.setActive(true)
        result(true)
      } catch { result(false) }
    case "deviceInfo":
      var sys = utsname(); uname(&sys)
      let model = withUnsafePointer(to: &sys.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
      }
      result(["model": model,
              "os_version": "iOS \(UIDevice.current.systemVersion)"])
    default: result(FlutterMethodNotImplemented)
    }
  }
  ```

  Khi app đã tự đặt session, plugin được báo `manageAudioSession: false` để
  không ghi đè. Chưa có handler này thì app vẫn thu được, nhưng ghi
  `unprocessed_source = false` và phiên mang cờ `os_processing_possible`.

Nguồn thực tế ghi vào `mic_source`, kèm `unprocessed_source = true/false`.

**Đo chất lượng trên file, cùng định nghĩa với server.** `audio_metrics.dart`
tính `noise_floor_db` (từ phần A), `speech_db` (phân vị 90 RMS khung 20 ms),
`peak_db`, `snr_db`, `clipping_ratio`, `speech_sec` đúng như backend
`app/quality.py`. Server tính lại trên bản thô và gắn `quality_mismatch` khi
lệch, nên hai phía phải khớp: `test/audio_metrics_test.dart` so với số liệu
do chính `quality.py` sinh trên `test/fixtures/contract_*.wav`. Sửa định nghĩa
đo ở một phía thì sinh lại fixture từ phía kia.

**VAD chỉ để đếm, không để cắt.** Biên độ realtime chỉ dùng hiện tiến độ
"Speaking time" và cảnh báo ồn. Quyết định gắn cờ luôn dựa trên số đo trên
file sau khi thu.

**Gắn cờ, không loại bỏ; không thu đè (mục 6).** Cổng chất lượng gắn
`low_snr`, `clipping`, `below_measurement_threshold`,
`os_processing_possible`, `stopped_early` rồi vẫn lưu và tải lên. Phiên duy
nhất bị từ chối (không lưu, không tính vào lịch) là phiên gần như im lặng
toàn bộ. Không có nút nghe lại hay thu lại phiên vừa xong — chỉ gợi ý thu
thêm một phiên mới. Thu đè tạo ra chọn lọc theo cảm nhận của người dùng về
giọng mình.

**Bệnh nhân không bao giờ thấy điểm (mục 11).** Bệnh nhân chỉ thấy số phiên đã
thu, chất lượng thu của phiên vừa rồi kèm hướng dẫn (chỗ yên tĩnh hơn, cầm máy
xa/gần hơn) và đường dẫn tới hỗ trợ. Không có từ ngữ chẩn đoán. Lịch tháng chỉ
có hai trạng thái đã thu / chưa thu.

**`device_id` là mã ẩn danh sinh một lần khi cài app**, lưu ở
`shared_preferences` để không mất khi đăng xuất. Không phải IMEI hay mã phần
cứng. `recording_context` (home / clinic / lab) do người dùng chọn đầu phiên,
nhớ lựa chọn lần trước.

**Hàng đợi tải lên, không gọi API trực tiếp.** `UploadQueue` lưu việc chờ
xuống đĩa, tồn tại qua lần khởi động app, tự chạy lại khi có mạng, và **chỉ
xoá ba file cục bộ sau khi checksum từng phần khớp với máy chủ**. Gửi lại cùng
`session_id` thì server trả lại phiên đã lưu (`already_received`), không ghi đè.

Ba nhánh xử lý lỗi khác nhau, không gộp làm một:
- Lỗi mạng hoặc 5xx → thử lại với backoff luỹ thừa (2s, 4s, 8s... tối đa 6 lần)
- 401 → token hết hạn, đăng xuất luôn thay vì đốt hết lượt thử lại
- 4xx khác (sai sample rate, file quá lớn) → dừng hẳn, vì thử lại cho kết quả y hệt

## Còn thiếu để lên bản thật

- Onboarding (hiện vào thẳng màn đăng nhập)
- Lịch nhắc thật (`flutter_local_notifications`) — mặc định mỗi ngày một phiên, cùng khung giờ (mục 3)
- Handler iOS cho kênh `voice_journal/audio` (xem trên) khi tạo thư mục `ios/`
- Chuyển lưu trữ từ `shared_preferences` sang sqflite/Isar
- Mã hoá file âm thanh trên thiết bị
