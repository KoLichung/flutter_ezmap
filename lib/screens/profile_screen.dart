import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 搜索
          _buildMenuItem(
            context,
            icon: Icons.search,
            title: '搜索',
            subtitle: '搜尋路線和記錄',
            onTap: () {
              // TODO: 導航到搜索頁面
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('搜索功能開發中...')),
              );
            },
          ),
          const Divider(),
          
          // 已下載路線
          _buildMenuItem(
            context,
            icon: Icons.download_done,
            title: '已下載路線',
            subtitle: '查看已下載的路線',
            onTap: () {
              // TODO: 導航到已下載路線頁面
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已下載路線功能開發中...')),
              );
            },
          ),
          const Divider(),
          
          // 我的紀錄
          _buildMenuItem(
            context,
            icon: Icons.history,
            title: '我的紀錄',
            subtitle: '查看過去的活動記錄',
            onTap: () {
              // TODO: 導航到活動列表頁面
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('我的紀錄功能開發中...')),
              );
            },
          ),
          const Divider(),
          
          // 地圖包
          _buildMenuItem(
            context,
            icon: Icons.map,
            title: '地圖包',
            subtitle: '管理離線地圖',
            onTap: () {
              // TODO: 導航到地圖包管理頁面
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('地圖包功能開發中...')),
              );
            },
          ),
          const Divider(),
          
          const SizedBox(height: 24),
          
          // 設定
          _buildMenuItem(
            context,
            icon: Icons.settings,
            title: '設定',
            subtitle: 'App 設定',
            onTap: () {
              // TODO: 導航到設定頁面
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('設定功能開發中...')),
              );
            },
          ),
          const Divider(),
          
          // 關於
          _buildMenuItem(
            context,
            icon: Icons.info_outline,
            title: '關於',
            subtitle: '關於 EzMap',
            onTap: () {
              _showAboutDialog(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: Colors.green.shade700,
          size: 28,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.grey.shade400,
      ),
      onTap: onTap,
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('關於 EzMap'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本: 1.0.0'),
            SizedBox(height: 8),
            Text('簡易登山導航 App'),
            SizedBox(height: 8),
            Text('提供離線地圖、GPS 軌跡記錄和導航功能'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
}

