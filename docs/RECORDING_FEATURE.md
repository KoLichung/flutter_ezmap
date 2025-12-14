# 记录功能技术文档

## 概述

本文档描述"开始记录"功能的实现方案，包括两个主要需求：
1. 记录时行走的路线使用咖啡色显示
2. 支持后台执行时继续记录

---

## 需求分析

### 需求 1: 咖啡色轨迹线

**当前状态：**
- 记录中的轨迹线使用红色 (`Colors.red`) 显示
- 位置：`lib/screens/journey_screen.dart` 第 179-197 行

**实现方案：**
- 将轨迹线颜色从红色改为咖啡色
- 咖啡色定义：`Color(0xFF8B4513)` 或 `Colors.brown.shade700`

**影响范围：**
- `lib/screens/journey_screen.dart` - 修改轨迹线颜色

**技术复杂度：** ⭐ (简单)

---

### 需求 2: 后台记录功能

**当前状态：**
- 记录功能仅在应用前台运行时有效
- 应用进入后台或被杀死时，GPS 监听会停止
- 数据仅保存在内存中，应用重启会丢失

**实现方案：**

#### 2.1 架构设计

```
┌─────────────────────────────────────────────┐
│         Foreground Recording                 │
│    (当前实现 - RecordingProvider)             │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│      Background Recording Service            │
│    (新增 - BackgroundRecordingService)       │
│  - 使用 isolate 在后台运行                    │
│  - 定期保存数据到本地数据库                   │
│  - 显示通知栏状态                            │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│      Persistent Storage                      │
│    (使用 sqflite 数据库)                      │
│  - 保存 Activity 数据                        │
│  - 保存 TrackPoint 数据                      │
│  - 支持断点续传                              │
└─────────────────────────────────────────────┘
```

#### 2.2 技术组件

**2.2.1 后台服务 (Background Service)**

- **技术选型：**
  - `flutter_background_service` - 提供后台服务能力
  - `workmanager` - 用于定期任务（备选方案）
  
- **功能要求：**
  - 应用进入后台时自动启动后台服务
  - 使用 isolate 运行，不阻塞主线程
  - 定期保存轨迹数据到数据库（每 10-30 秒）
  - 应用恢复时同步数据

**2.2.2 权限管理**

- **Android 权限：**
  ```xml
  <!-- AndroidManifest.xml -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
  <uses-permission android:name="android.permission.WAKE_LOCK" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  ```

- **iOS 权限：**
  ```xml
  <!-- Info.plist -->
  <key>UIBackgroundModes</key>
  <array>
    <string>location</string>
  </array>
  ```

- **权限检查：**
  - 使用 `permission_handler` 检查后台定位权限
  - 在开始记录前请求必要权限

**2.2.3 数据持久化**

- **数据库设计：**
  ```sql
  -- activities 表
  CREATE TABLE activities (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    start_time INTEGER NOT NULL,
    end_time INTEGER,
    total_distance REAL DEFAULT 0,
    total_ascent REAL DEFAULT 0,
    total_descent REAL DEFAULT 0,
    max_speed REAL DEFAULT 0,
    avg_speed REAL DEFAULT 0,
    moving_time INTEGER DEFAULT 0,
    total_time INTEGER DEFAULT 0,
    gpx_file_path TEXT,
    is_recording INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL
  );

  -- track_points 表
  CREATE TABLE track_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    activity_id TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude REAL,
    speed REAL,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (activity_id) REFERENCES activities(id)
  );
  CREATE INDEX idx_track_points_activity ON track_points(activity_id);
  CREATE INDEX idx_track_points_timestamp ON track_points(timestamp);
  ```

- **数据同步策略：**
  - 前台记录：实时更新内存，每 30 秒保存到数据库
  - 后台记录：每 10-30 秒保存一次
  - 应用启动时：检查是否有未完成的记录，恢复状态

**2.2.4 通知栏显示**

- **通知内容：**
  - 标题：正在记录轨迹
  - 内容：显示记录时长、距离、速度
  - 操作按钮：暂停/继续、停止记录

- **实现方式：**
  - 使用 `flutter_local_notifications` 或 `flutter_background_service` 内置通知
  - 定期更新通知内容（每 5-10 秒）

**2.2.5 状态同步**

- **前台 ↔ 后台同步：**
  - 使用 `SharedPreferences` 或数据库存储当前记录状态
  - 前台启动时检查是否有后台记录，自动同步
  - 后台启动时检查是否有前台记录，接管记录

- **数据一致性：**
  - 使用事务确保数据完整性
  - 记录结束时合并所有数据

#### 2.3 实现步骤

**Phase 1: 数据持久化层**
1. 创建数据库服务 (`lib/services/database_service.dart`)
2. 实现 Activity 和 TrackPoint 的 CRUD 操作
3. 添加批量插入 TrackPoint 的方法
4. 实现数据恢复功能

**Phase 2: 后台服务基础**
1. 集成 `flutter_background_service`
2. 配置 Android/iOS 权限
3. 实现基础的后台服务启动/停止
4. 测试后台服务生命周期

**Phase 3: GPS 后台监听**
1. 在后台服务中启动 GPS 监听
2. 实现位置数据收集
3. 实现定期保存机制
4. 处理 GPS 权限和错误

**Phase 4: 通知栏集成**
1. 创建通知栏 UI
2. 实现通知更新机制
3. 添加操作按钮（暂停/停止）
4. 处理通知点击事件

**Phase 5: 前后台同步**
1. 实现状态同步机制
2. 处理应用恢复时的数据合并
3. 实现无缝切换（前台 ↔ 后台）
4. 添加数据一致性检查

**Phase 6: 优化和测试**
1. 性能优化（批量插入、索引优化）
2. 电池优化（降低更新频率）
3. 错误处理和恢复机制
4. 全面测试各种场景

#### 2.4 技术挑战

**挑战 1: 电池消耗**
- **问题：** 后台 GPS 监听会消耗大量电量
- **解决方案：**
  - 使用 `distanceFilter` 过滤不必要的位置更新
  - 根据速度动态调整更新频率
  - 使用低功耗模式（如果支持）

**挑战 2: 系统限制**
- **问题：** iOS/Android 对后台应用有严格限制
- **解决方案：**
  - iOS: 使用 `location` 后台模式
  - Android: 使用前台服务 + 通知
  - 处理系统杀死应用的情况（定期保存）

**挑战 3: 数据一致性**
- **问题：** 前后台切换时可能出现数据丢失
- **解决方案：**
  - 使用数据库事务
  - 定期保存检查点
  - 应用启动时检查未完成记录

**挑战 4: 性能问题**
- **问题：** 大量轨迹点可能导致性能问题
- **解决方案：**
  - 批量插入数据库
  - 使用索引优化查询
  - 定期清理旧数据

#### 2.5 依赖包

```yaml
dependencies:
  # 后台服务
  flutter_background_service: ^5.0.5
  
  # 通知
  flutter_local_notifications: ^17.0.0
  
  # 权限（已有）
  permission_handler: ^11.2.0
  
  # 数据库（已有）
  sqflite: ^2.3.2
  
  # 共享存储（已有）
  path_provider: ^2.1.2
```

#### 2.6 文件结构

```
lib/
├── services/
│   ├── database_service.dart          # 数据库服务（新增）
│   ├── background_recording_service.dart  # 后台记录服务（新增）
│   └── gps_service.dart                # GPS 服务（已有，需扩展）
│
├── providers/
│   └── recording_provider.dart        # 记录状态管理（需修改）
│
└── models/
    ├── activity.dart                  # 活动模型（已有）
    └── track_point.dart               # 轨迹点模型（已有）
```

---

## 实现优先级

### 高优先级（MVP）
1. ✅ 咖啡色轨迹线（简单，立即实现）
2. ✅ 数据持久化层（后台功能的基础）
3. ✅ 基础后台服务（核心功能）

### 中优先级
4. ⚠️ GPS 后台监听
5. ⚠️ 通知栏显示
6. ⚠️ 前后台同步

### 低优先级（优化）
7. 📋 性能优化
8. 📋 电池优化
9. 📋 错误恢复机制

---

## 测试场景

### 场景 1: 前台记录
- ✅ 开始记录 → 轨迹线显示为咖啡色
- ✅ 移动 → 轨迹实时更新
- ✅ 暂停/继续 → 状态正确
- ✅ 停止记录 → 数据保存

### 场景 2: 后台记录
- ⚠️ 开始记录 → 进入后台 → 继续记录
- ⚠️ 后台记录 → 通知栏显示状态
- ⚠️ 后台记录 → 应用被杀死 → 重启后恢复
- ⚠️ 后台记录 → 返回前台 → 数据同步

### 场景 3: 前后台切换
- ⚠️ 前台记录 → 进入后台 → 后台继续
- ⚠️ 后台记录 → 返回前台 → 前台继续
- ⚠️ 多次切换 → 数据一致性

### 场景 4: 异常情况
- ⚠️ GPS 权限被撤销
- ⚠️ 应用被系统杀死
- ⚠️ 电池耗尽
- ⚠️ 网络断开（如果有同步功能）

---

## 风险评估

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 后台服务被系统杀死 | 高 | 中 | 定期保存数据，启动时恢复 |
| 电池消耗过高 | 高 | 高 | 优化更新频率，使用低功耗模式 |
| iOS 后台限制 | 中 | 中 | 使用 location 后台模式 |
| 数据丢失 | 高 | 低 | 定期保存，使用事务 |
| 性能问题 | 中 | 中 | 批量操作，索引优化 |

---

## 参考资料

- [Flutter Background Service](https://pub.dev/packages/flutter_background_service)
- [Geolocator Background Location](https://pub.dev/packages/geolocator#background-location-updates)
- [Android Foreground Services](https://developer.android.com/guide/components/foreground-services)
- [iOS Background Modes](https://developer.apple.com/documentation/backgroundtasks)
- [SQLite Best Practices](https://www.sqlite.org/bestpractices.html)

---

## 更新日志

- 2024-XX-XX: 初始版本，需求分析和架构设计

