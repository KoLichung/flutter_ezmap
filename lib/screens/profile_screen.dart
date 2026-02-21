import 'package:flutter/material.dart';
import 'downloaded_routes_screen.dart';
import 'my_records_screen.dart';

class ProfileScreen extends StatelessWidget {
  final Function(int)? onSwitchTab;
  
  const ProfileScreen({super.key, this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的健行地圖'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 頭像和用戶信息
          _buildUserSection(context),
          const SizedBox(height: 24),
          
          // 已下載路線
          _buildMenuItem(
            context,
            icon: Icons.download_done,
            title: '已下載路線',
            onTap: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const DownloadedRoutesScreen(),
                ),
              );
              
              // 如果返回 true，表示需要切换到旅程 tab
              if (result == true && onSwitchTab != null) {
                onSwitchTab!(0); // 切换到 index 0（旅程 tab）
              }
            },
          ),
          const Divider(height: 1),
          
          // 我的紀錄
          _buildMenuItem(
            context,
            icon: Icons.history,
            title: '我的紀錄',
            onTap: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyRecordsScreen(),
                ),
              );
              if (result == true && onSwitchTab != null) {
                onSwitchTab!(0);
              }
            },
          ),
          const Divider(height: 1),
          
          const SizedBox(height: 16),
          
          // 版本號（居中）
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '版本號 1.0.0',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 用戶信息區域
  Widget _buildUserSection(BuildContext context) {
    // TODO: 從狀態管理獲取用戶登錄狀態
    final bool isLoggedIn = false; // 暫時設為未登錄
    final String userName = 'User Name'; // 暫時的用戶名
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 頭像
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.green.shade700,
            child: Icon(
              Icons.person,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          
          // 用戶名或登錄按鈕
          Expanded(
            child: isLoggedIn
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '查看個人資料',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '尚未登錄',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('登錄功能開發中...')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                        ),
                        child: const Text('登錄'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: Colors.green.shade700,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.grey.shade400,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

