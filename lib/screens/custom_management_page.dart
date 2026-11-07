import 'package:flutter/material.dart';

import 'color_settings_page.dart';
import 'custom_fields_page.dart';
import 'custom_image_gallery_page.dart';
import 'pre_trade_management_page.dart';

class CustomManagementPage extends StatelessWidget {
  const CustomManagementPage({
    super.key,
  });

  Widget _buildItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.assetIconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppColors.assetIcon, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(color: AppColors.secondaryText, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: AppColors.chevron),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPage(BuildContext context, Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('موارد سفارشی'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'مدیریت فرم معامله',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            'مواردی که می‌خواهید هنگام ثبت معامله نمایش داده شوند را مدیریت کنید.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 20),
          _buildItem(
            context: context,
            title: 'فیلدهای سفارشی',
            subtitle: 'افزودن فیلدهای متن، عدد، درصد، مبلغ، تاریخ و لیست انتخابی',
            icon: Icons.tune,
            onTap: () => _openPage(context, const CustomFieldsPage()),
          ),
          _buildItem(
            context: context,
            title: 'سؤالات و چک‌لیست‌ها',
            subtitle: 'مدیریت سؤالات پیش از معامله و چک‌لیست روانشناسی و تکنیکال',
            icon: Icons.checklist_outlined,
            onTap: () => _openPage(context, const PreTradeManagementPage()),
          ),
          _buildItem(
            context: context,
            title: 'گالری عکس',
            subtitle: 'ساخت موضوع و ذخیره چندین عکس در هر موضوع',
            icon: Icons.photo_library_outlined,
            onTap: () => _openPage(context, const CustomImageGalleryPage()),
          ),
        ],
      ),
    );
  }
}
