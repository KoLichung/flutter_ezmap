# EzMap 简单架构设计

## 架构理念

**保持简单，快速开发！**

采用 **Provider + Service** 模式，适合中小型 App，学习曲线平缓，容易上手。

---

## 整体架构图

```
┌─────────────────────────────────────────┐
│           UI Layer (Screens)             │
│        使用 Provider 监听状态变化          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      State Management (Providers)        │
│     管理状态，通知 UI 更新                 │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│         Services (业务逻辑)               │
│    GPS, 数据库, GPX, 文件处理等            │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      Models (数据模型)                    │
│    Activity, TrackPoint, Waypoint       │
└─────────────────────────────────────────┘
```

---

## 目录结构

```
lib/
├── main.dart                          # 应用入口
│
├── models/                           # 数据模型
│   ├── activity.dart                # 活动模型
│   ├── track_point.dart             # 轨迹点模型
│   └── waypoint.dart                # 记录点模型
│
├── providers/                        # 状态管理
│   ├── recording_provider.dart      # 记录状态管理
│   ├── map_provider.dart            # 地图状态管理
│   ├── activity_provider.dart       # 活动列表管理
│   └── settings_provider.dart       # 设置管理
│
├── services/                         # 业务服务
│   ├── gps_service.dart             # GPS 定位服务
│   ├── database_service.dart        # 数据库服务
│   ├── gpx_service.dart             # GPX 文件处理
│   ├── compass_service.dart         # 指南针服务
│   └── permission_service.dart      # 权限管理
│
├── screens/                          # 页面
│   ├── map_screen.dart              # 地图主页面
│   ├── activity_list_screen.dart    # 活动列表
│   ├── activity_detail_screen.dart  # 活动详情
│   ├── waypoint_screen.dart         # 记录点管理
│   └── settings_screen.dart         # 设置页面
│
├── widgets/                          # 共用组件
│   ├── stats_panel.dart             # 数据面板
│   ├── record_button.dart           # 记录按钮
│   ├── compass_widget.dart          # 指南针组件
│   └── elevation_chart.dart         # 高度图表
│
└── utils/                            # 工具函数
    ├── constants.dart               # 常数
    ├── helpers.dart                 # 辅助函数
    └── calculators.dart             # 计算函数（距离、高度等）
```

---

## 核心组件说明

### 1. Models (数据模型)

简单的 Dart 类，用于表示数据结构。

```dart
// models/activity.dart
class Activity {
  String id;
  String name;
  DateTime startTime;
  DateTime? endTime;
  List<TrackPoint> trackPoints;
  
  // 构造函数
  // toJson / fromJson 方法
}
```

**包含的模型:**
- `Activity` - 活动
- `TrackPoint` - 轨迹点
- `Waypoint` - 记录点
- `ActivityStats` - 统计数据

---

### 2. Services (业务服务)

处理具体的业务逻辑，如 GPS 定位、数据库操作等。

```dart
// services/gps_service.dart
class GpsService {
  // 获取当前位置
  Future<Position> getCurrentPosition() {}
  
  // 监听位置变化
  Stream<Position> getPositionStream() {}
  
  // 检查权限
  Future<bool> checkPermission() {}
}
```

**主要服务:**
- `GpsService` - GPS 定位
- `DatabaseService` - SQLite 数据库
- `GpxService` - GPX 文件处理
- `CompassService` - 指南针
- `PermissionService` - 权限管理

---

### 3. Providers (状态管理)

使用 Provider 管理状态，当数据变化时自动通知 UI 更新。

```dart
// providers/recording_provider.dart
class RecordingProvider extends ChangeNotifier {
  Activity? _currentActivity;
  bool _isRecording = false;
  Position? _currentPosition;
  
  // Getters
  Activity? get currentActivity => _currentActivity;
  bool get isRecording => _isRecording;
  
  // 开始记录
  void startRecording() {
    _isRecording = true;
    _currentActivity = Activity(...);
    notifyListeners(); // 通知 UI 更新
  }
  
  // 暂停记录
  void pauseRecording() {
    _isRecording = false;
    notifyListeners();
  }
  
  // 添加轨迹点
  void addTrackPoint(Position position) {
    _currentPosition = position;
    _currentActivity?.trackPoints.add(...);
    notifyListeners();
  }
}
```

**主要 Providers:**
- `RecordingProvider` - 记录控制和状态
- `MapProvider` - 地图状态（缩放、中心点等）
- `ActivityProvider` - 活动列表
- `SettingsProvider` - 应用设置

---

### 4. Screens (页面)

使用 Provider 的数据，构建 UI。

```dart
// screens/map_screen.dart
class MapScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingProvider>(
      builder: (context, recordingProvider, child) {
        return Scaffold(
          body: Stack(
            children: [
              // 地图
              FlutterMap(...),
              
              // 数据面板
              StatsPanel(
                stats: recordingProvider.currentStats,
              ),
              
              // 记录按钮
              RecordButton(
                isRecording: recordingProvider.isRecording,
                onStart: () => recordingProvider.startRecording(),
                onPause: () => recordingProvider.pauseRecording(),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

**主要页面:**
- `MapScreen` - 地图主页（带记录功能）
- `ActivityListScreen` - 活动列表
- `ActivityDetailScreen` - 活动详情（统计+图表）
- `WaypointScreen` - 记录点管理
- `SettingsScreen` - 设置

---

## 数据流向

### 用户开始记录

```
1. 用户点击"开始记录"按钮
   ↓
2. MapScreen 调用 RecordingProvider.startRecording()
   ↓
3. RecordingProvider 调用 GpsService.getPositionStream()
   ↓
4. GPS 持续回传位置数据
   ↓
5. RecordingProvider 接收位置 → 添加到 trackPoints
   ↓
6. RecordingProvider.notifyListeners() 通知 UI
   ↓
7. MapScreen 自动重新 build，显示新数据
```

### 保存活动

```
1. 用户点击"结束记录"
   ↓
2. RecordingProvider.stopRecording()
   ↓
3. 调用 DatabaseService.saveActivity()
   ↓
4. 调用 GpxService.exportGpx()
   ↓
5. 保存完成，清空当前活动
   ↓
6. 跳转到活动详情页
```

---

## 关键实现要点

### 1. main.dart 设置

```dart
void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => ActivityProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MyApp(),
    ),
  );
}
```

### 2. Service 初始化

```dart
// 在 Provider 中初始化 Service
class RecordingProvider extends ChangeNotifier {
  final GpsService _gpsService = GpsService();
  final DatabaseService _dbService = DatabaseService();
  
  // 或使用单例模式
  final GpsService _gpsService = GpsService.instance;
}
```

### 3. 数据持久化

```dart
// DatabaseService 使用 sqflite
class DatabaseService {
  Database? _db;
  
  Future<void> init() async {
    _db = await openDatabase('ezmap.db');
  }
  
  Future<void> saveActivity(Activity activity) async {
    await _db?.insert('activities', activity.toJson());
  }
  
  Future<List<Activity>> getActivities() async {
    final results = await _db?.query('activities');
    return results?.map((r) => Activity.fromJson(r)).toList() ?? [];
  }
}
```

---

## 为什么选择这个架构？

### ✅ 优点

1. **简单易懂** - 只有 4 层，概念清晰
2. **快速开发** - 不需要写太多抽象层
3. **容易维护** - 代码组织清楚，容易找到文件
4. **学习曲线平缓** - Provider 是 Flutter 官方推荐
5. **足够应对** - 对于中型 App 完全够用

### 📝 适用场景

- ✅ 单人或小团队开发
- ✅ 中小型项目（<50 个页面）
- ✅ 快速原型开发
- ✅ 学习 Flutter

### ⚠️ 局限性

- 如果项目变得很大（100+ 页面），可能需要重构
- 测试相对困难（比 Clean Architecture）
- Service 层可能会变得臃肿

---

## 开发顺序建议

### Week 1: 基础架构

1. 创建目录结构
2. 定义基本 Models
3. 设置 Provider
4. 创建基本页面框架

### Week 2: 地图与 GPS

1. 实现 GpsService
2. 实现 MapProvider
3. 显示地图和当前位置
4. 测试 GPS 定位

### Week 3: 记录功能

1. 实现 RecordingProvider
2. 实现记录控制（开始/暂停/结束）
3. 实现 DatabaseService
4. 保存和读取活动

### Week 4: 数据显示

1. 实现统计计算
2. 创建数据面板 Widget
3. 实现活动列表
4. 实现活动详情页

---

## 常用模式

### 监听数据变化

```dart
// 方式 1: Consumer
Consumer<RecordingProvider>(
  builder: (context, provider, child) {
    return Text('距离: ${provider.distance}');
  },
)

// 方式 2: Provider.of
final provider = Provider.of<RecordingProvider>(context);
Text('距离: ${provider.distance}');

// 方式 3: context.watch (推荐)
final provider = context.watch<RecordingProvider>();
Text('距离: ${provider.distance}');
```

### 调用方法（不监听）

```dart
// 只调用方法，不重建 Widget
context.read<RecordingProvider>().startRecording();
```

### 异步操作

```dart
class RecordingProvider extends ChangeNotifier {
  bool _isLoading = false;
  
  Future<void> loadActivities() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _activities = await _dbService.getActivities();
    } catch (e) {
      // 处理错误
    }
    
    _isLoading = false;
    notifyListeners();
  }
}
```

---

## 核心代码示例

### 完整的 RecordingProvider

```dart
class RecordingProvider extends ChangeNotifier {
  final GpsService _gpsService = GpsService();
  final DatabaseService _dbService = DatabaseService();
  
  Activity? _currentActivity;
  bool _isRecording = false;
  bool _isPaused = false;
  Position? _currentPosition;
  StreamSubscription? _positionSubscription;
  
  // Getters
  Activity? get currentActivity => _currentActivity;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Position? get currentPosition => _currentPosition;
  
  // 计算统计数据
  ActivityStats get currentStats {
    if (_currentActivity == null) return ActivityStats.empty();
    return ActivityStats.calculate(_currentActivity!.trackPoints);
  }
  
  // 开始记录
  Future<void> startRecording(String name) async {
    _currentActivity = Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      startTime: DateTime.now(),
      trackPoints: [],
    );
    
    _isRecording = true;
    _isPaused = false;
    
    // 监听 GPS
    _positionSubscription = _gpsService
        .getPositionStream()
        .listen(_onPositionUpdate);
    
    notifyListeners();
  }
  
  // GPS 数据更新
  void _onPositionUpdate(Position position) {
    _currentPosition = position;
    
    if (!_isPaused) {
      _currentActivity?.trackPoints.add(
        TrackPoint.fromPosition(position),
      );
    }
    
    notifyListeners();
  }
  
  // 暂停
  void pauseRecording() {
    _isPaused = true;
    notifyListeners();
  }
  
  // 继续
  void resumeRecording() {
    _isPaused = false;
    notifyListeners();
  }
  
  // 结束
  Future<void> stopRecording() async {
    _currentActivity?.endTime = DateTime.now();
    
    // 保存到数据库
    if (_currentActivity != null) {
      await _dbService.saveActivity(_currentActivity!);
    }
    
    // 清理
    await _positionSubscription?.cancel();
    _isRecording = false;
    _isPaused = false;
    _currentActivity = null;
    
    notifyListeners();
  }
  
  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}
```

---

## 总结

这个架构：

- ✅ **简单** - 4 层结构，容易理解
- ✅ **实用** - 满足 EzMap 所有需求
- ✅ **高效** - 快速开发，容易维护
- ✅ **灵活** - 未来可以逐步优化

**开始开发吧！** 🚀

---

**文档版本**: v1.0  
**最后更新**: 2025-11-06

