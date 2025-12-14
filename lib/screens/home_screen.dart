import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recording_provider.dart';
import 'journey_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    
    // 初始化 screens 列表
    _screens = [
      const JourneyScreen(),
      ProfileScreen(onSwitchTab: _switchTab),
    ];
    
    // 初始化 GPS 位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordingProvider>().initializePosition();
    });
  }
  
  // 切換 tab 的方法
  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingProvider>(
      builder: (context, recordingProvider, child) {
        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: recordingProvider.isRecording
              ? _buildRecordingControls(recordingProvider)
              : BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  selectedItemColor: Colors.green.shade700,
                  unselectedItemColor: Colors.grey,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.map),
                      label: '旅程',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person),
                      label: '我的',
                    ),
                  ],
                ),
        );
      },
    );
  }

  // 記錄中的控制區域（4個按鈕一排，類似 tab 樣式）
  Widget _buildRecordingControls(RecordingProvider recordingProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 統計信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                const Text(
                  '00:00:00',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.straighten,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  '${recordingProvider.currentDistance.toStringAsFixed(2)} km',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_upward,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  '${recordingProvider.currentAscent.toStringAsFixed(0)} m',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.arrow_downward,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  '${recordingProvider.currentDescent.toStringAsFixed(0)} m',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // 四個按鈕一排（類似 tab 樣式）
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // 活動分析
                  _buildTabButton(
                    icon: Icons.analytics_outlined,
                    label: '活動分析',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('活動分析功能開發中...')),
                      );
                    },
                  ),
                  
                  // 添加紀錄點
                  _buildTabButton(
                    icon: Icons.add_location_outlined,
                    label: '紀錄點',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('添加紀錄點功能開發中...')),
                      );
                    },
                  ),
                  
                  // 暫停/繼續
                  _buildTabButton(
                    icon: recordingProvider.isPaused
                        ? Icons.play_arrow
                        : Icons.pause,
                    label: recordingProvider.isPaused ? '繼續' : '暫停',
                    color: recordingProvider.isPaused
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    onTap: () {
                      if (recordingProvider.isPaused) {
                        recordingProvider.resumeRecording();
                      } else {
                        recordingProvider.pauseRecording();
                      }
                    },
                  ),
                  
                  // 結束
                  _buildTabButton(
                    icon: Icons.stop,
                    label: '結束',
                    color: Colors.red.shade700,
                    onTap: () {
                      _showStopRecordingDialog(context, recordingProvider);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final buttonColor = color ?? Colors.grey.shade700;
    
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: buttonColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: buttonColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStopRecordingDialog(
    BuildContext context,
    RecordingProvider recordingProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('結束記錄'),
        content: const Text('確定要結束記錄嗎？軌跡將會被保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              recordingProvider.stopRecording();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('記錄已保存')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('結束'),
          ),
        ],
      ),
    );
  }
}

