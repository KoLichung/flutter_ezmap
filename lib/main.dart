import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'providers/recording_provider.dart';
import 'providers/map_provider.dart';
import 'screens/new_journey_screen.dart';
import 'services/route_service.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const platform = MethodChannel('com.chijia.flutter_ezmap/shared_file');
  StreamSubscription? _fileStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _handleInitialSharedFile();
    _handleIncomingSharedFile();
  }

  @override
  void dispose() {
    _fileStreamSubscription?.cancel();
    super.dispose();
  }

  // 處理應用啟動時接收到的檔案
  Future<void> _handleInitialSharedFile() async {
    try {
      final filePath = await platform.invokeMethod<String>(
        'getInitialSharedFile',
      );
      if (filePath != null && filePath.isNotEmpty) {
        _processSharedFile(filePath);
      }
    } catch (e) {
      print('Error getting initial shared file: $e');
    }
  }

  // 處理應用運行時接收到的檔案
  void _handleIncomingSharedFile() {
    const EventChannel eventChannel = EventChannel(
      'com.chijia.flutter_ezmap/shared_file_stream',
    );
    _fileStreamSubscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic filePath) {
        if (filePath != null && filePath is String) {
          _processSharedFile(filePath);
        }
      },
      onError: (err) {
        print('Error receiving shared file: $err');
      },
    );
  }

  Future<void> _processSharedFile(String filePath) async {
    print('Processing shared file: $filePath');
    if (filePath.endsWith('.gpx')) {
      try {
        final savedPath = await RouteService.importGpxFile(filePath);
        if (savedPath != null && navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text('已匯入 GPX 檔案：${filePath.split('/').last}'),
              duration: const Duration(seconds: 3),
            ),
          );

          // 如果當前在已下載路線頁面，需要刷新列表
          // 這裡可以通過 Provider 或 EventBus 來通知頁面刷新
          // 暫時先記錄，實際刷新會在用戶返回該頁面時自動觸發
        }
      } catch (e) {
        print('Error processing shared GPX file: $e');
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text('匯入 GPX 檔案失敗: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      print('File is not a GPX file: $filePath');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'EzMap - 簡易登山導航',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E7D32), // 登山綠
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        home: Builder(
          builder: (context) {
            // 初始化 GPS 位置
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<RecordingProvider>().initializePosition();
            });
            return const NewJourneyScreen();
          },
        ),
      ),
    );
  }
}
