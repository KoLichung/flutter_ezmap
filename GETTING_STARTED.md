# EzMap - 快速開始指南

## 專案結構

```
lib/
├── main.dart                          # 應用入口
├── models/                           # 數據模型
│   ├── activity.dart                # 活動模型
│   ├── track_point.dart             # 軌跡點模型
│   └── waypoint.dart                # 記錄點模型
├── providers/                        # 狀態管理
│   ├── recording_provider.dart      # 記錄狀態管理
│   └── map_provider.dart            # 地圖狀態管理
├── services/                         # 業務服務
│   └── gps_service.dart             # GPS 定位服務
├── screens/                          # 頁面
│   ├── home_screen.dart             # 主頁（Tab 容器）
│   ├── journey_screen.dart          # 旅程頁（地圖+記錄）
│   └── profile_screen.dart          # 我的頁（功能列表）
└── widgets/                          # 共用組件
    ├── stats_panel.dart             # 數據面板
    └── record_control.dart          # 記錄控制按鈕
```

## 已實現功能

### ✅ 首頁架構
- 雙 Tab 切換：旅程 / 我的
- 底部記錄控制面板

### ✅ 旅程頁面
- 地圖顯示（使用 flutter_map + OpenStreetMap）
- 座標和高度顯示卡片
- 指北針和定位按鈕
- GPS 軌跡記錄功能
- 暫停/繼續記錄
- 記錄狀態顯示

### ✅ 我的頁面
- 搜索
- 已下載路線
- 我的紀錄
- 地圖包
- 設定
- 關於

## 運行應用

### 1. 安裝依賴
```bash
flutter pub get
```

### 2. 運行到設備/模擬器
```bash
# iOS 模擬器
flutter run

# Android 模擬器
flutter run

# 特定設備
flutter run -d <device_id>
```

### 3. 查看可用設備
```bash
flutter devices
```

## 地圖配置

### 當前配置
- **地圖源**: OpenStreetMap（線上）
- **中心點**: 台灣中心 (23.5, 121.0)
- **縮放範圍**: 5-18

### 離線地圖配置（待完成）
要使用離線地圖，需要：
1. 下載台灣地區的 MBTiles 地圖包
2. 將地圖包放到 `assets/maps/` 目錄
3. 修改 `journey_screen.dart` 中的 TileLayer 配置
4. 在 `pubspec.yaml` 中添加 assets

示例：
```dart
// 離線地圖配置
TileLayer(
  tileProvider: AssetTileProvider(),
  urlTemplate: 'assets/maps/taiwan/{z}/{x}/{y}.png',
  maxZoom: 16,
)
```

## GPS 權限

### Android
已在 `AndroidManifest.xml` 添加：
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `INTERNET`

### iOS
已在 `Info.plist` 添加：
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationAlwaysUsageDescription`

## 測試建議

### 1. 測試地圖顯示
- 打開 App，切換到「旅程」頁面
- 確認地圖正常載入
- 測試縮放、平移功能

### 2. 測試 GPS 定位
- 點擊定位按鈕
- 確認權限請求彈窗
- 授權後確認地圖移動到當前位置
- 查看座標和高度卡片是否顯示數據

### 3. 測試軌跡記錄
- 點擊底部「開始記錄」按鈕
- 確認開始記錄（按鈕變為紅色「結束」）
- 移動設備，觀察紅色軌跡線是否繪製
- 測試暫停/繼續功能
- 點擊結束，確認記錄保存

### 4. 測試 Tab 切換
- 切換到「我的」頁面
- 查看功能列表
- 點擊各項功能（目前顯示開發中提示）

## 下一步開發

1. **數據持久化**
   - 實現 SQLite 數據庫
   - 保存活動記錄到本地
   - 實現「我的紀錄」列表頁

2. **離線地圖**
   - 下載台灣地圖包
   - 配置離線地圖顯示
   - 實現地圖包管理功能

3. **GPX 匯入/匯出**
   - 實現 GPX 檔案匯出
   - 實現參考路線匯入
   - 路線對比顯示

4. **數據分析**
   - 高度圖表
   - 速度圖表
   - 活動統計報告

5. **進階功能**
   - 指南針整合
   - 記錄點管理
   - 距離測量工具

## 注意事項

- **模擬器測試**: iOS 模擬器可以模擬位置，Android 模擬器也可以
- **真機測試**: 建議在戶外真機測試 GPS 記錄功能
- **背景定位**: 目前未實現背景定位，記錄時需保持 App 前景運行
- **電池優化**: 長時間記錄會消耗電池，建議使用行動電源

## 常見問題

### Q: 地圖無法載入
A: 確認設備有網路連接（當前使用線上地圖）

### Q: 定位按鈕無反應
A: 檢查是否授權 GPS 權限，iOS 需要在設定中手動授權

### Q: 軌跡線不顯示
A: 確認已開始記錄且設備正在移動（模擬器可用「位置模擬」）

### Q: 如何在模擬器中測試
A: 
- iOS: Features -> Location -> Custom Location / City Run
- Android: Extended Controls -> Location -> 設定路線

## 貢獻

歡迎提交 Issue 和 Pull Request！

## 授權

MIT License

