import 'package:flutter/material.dart';

import '../models/custom_field.dart';
import '../repositories/custom_field_repository.dart';
import 'color_settings_page.dart';
import 'quick_websites_page.dart';

class CustomFieldsPage extends StatefulWidget {
  const CustomFieldsPage({
    super.key,
  });

  @override
  State<CustomFieldsPage> createState() => _CustomFieldsPageState();
}

class _CustomFieldsPageState extends State<CustomFieldsPage> {
  final CustomFieldRepository _repository = CustomFieldRepository();

  List<CustomField> _fields = [];

  // =========================================================
  // CATEGORIES
  // =========================================================

  static const List<String> _categories = [
    'عمومی',
    'ورود به معامله',
    'تحلیل تکنیکال',
    'تحلیل بنیادی',
    'مدیریت سرمایه',
    'مدیریت ریسک',
    'روانشناسی',
    'مدیریت معامله',
    'خروج از معامله',
  ];

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _loadFields();
  }

  // =========================================================
  // LOAD FIELDS
  // =========================================================

  Future<void> _loadFields() async {
    final fields = await _repository.getAllFields();

    if (!mounted) {
      return;
    }

    setState(() {
      _fields = fields;
    });
  }

  // =========================================================
  // SHOW FIELD DIALOG
  // =========================================================

  Future<void> _showFieldDialog({
    CustomField? field,
  }) async {
    final nameController = TextEditingController(
      text: field?.fieldName ?? '',
    );

    final optionsController = TextEditingController(
      text: field?.options.join('\n') ?? '',
    );

    CustomFieldType selectedType = field?.fieldType ?? CustomFieldType.text;

    String selectedCategory = field?.category ?? 'عمومی';

    bool isRequired = field?.isRequired ?? false;

    bool isEnabled = field?.isEnabled ?? true;

    if (!_categories.contains(selectedCategory)) {
      selectedCategory = 'عمومی';
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                field == null ? 'افزودن فیلد' : 'ویرایش فیلد',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // =================================================
                    // FIELD NAME
                    // =================================================

                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'نام فیلد',
                        hintText: 'مثلاً دلیل ورود',
                      ),
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    // =================================================
                    // CATEGORY
                    // =================================================

                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'دسته‌بندی',
                      ),
                      items: _categories.map(
                        (
                          category,
                        ) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(
                              category,
                            ),
                          );
                        },
                      ).toList(),
                      onChanged: (
                        value,
                      ) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          selectedCategory = value;
                        });
                      },
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    // =================================================
                    // FIELD TYPE
                    // =================================================

                    DropdownButtonFormField<CustomFieldType>(
                      value: selectedType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'نوع فیلد',
                      ),
                      items: CustomFieldType.values.map(
                        (
                          type,
                        ) {
                          final temporaryField = CustomField(
                            fieldName: '',
                            fieldType: type,
                            createdAt: DateTime.now(),
                          );

                          return DropdownMenuItem<CustomFieldType>(
                            value: type,
                            child: Text(
                              temporaryField.typeName,
                            ),
                          );
                        },
                      ).toList(),
                      onChanged: (
                        value,
                      ) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          selectedType = value;
                        });
                      },
                    ),

                    // =================================================
                    // DROPDOWN OPTIONS
                    // =================================================

                    if (selectedType == CustomFieldType.dropdown) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      TextField(
                        controller: optionsController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'گزینه‌های لیست',
                          hintText: 'هر گزینه در یک خط',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],

                    const SizedBox(
                      height: 8,
                    ),

                    // =================================================
                    // REQUIRED
                    // =================================================

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'اجباری',
                      ),
                      subtitle: const Text(
                        'کاربر باید این فیلد را تکمیل کند',
                      ),
                      value: isRequired,
                      onChanged: (
                        value,
                      ) {
                        setDialogState(() {
                          isRequired = value;
                        });
                      },
                    ),

                    // =================================================
                    // ENABLED
                    // =================================================

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'فعال',
                      ),
                      subtitle: const Text(
                        'این فیلد در فرم معامله نمایش داده شود',
                      ),
                      value: isEnabled,
                      onChanged: (
                        value,
                      ) {
                        setDialogState(() {
                          isEnabled = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                // =================================================
                // CANCEL
                // =================================================

                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'انصراف',
                  ),
                ),

                // =================================================
                // SAVE
                // =================================================

                FilledButton(
                  onPressed: () async {
                    final fieldName = nameController.text.trim();

                    if (fieldName.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'نام فیلد را وارد کنید.',
                          ),
                        ),
                      );

                      return;
                    }

                    final options = optionsController.text
                        .split('\n')
                        .map(
                          (
                            item,
                          ) =>
                              item.trim(),
                        )
                        .where(
                          (
                            item,
                          ) =>
                              item.isNotEmpty,
                        )
                        .toList();

                    final newField = CustomField(
                      fieldId: field?.fieldId,
                      fieldName: fieldName,
                      fieldType: selectedType,
                      category: selectedCategory,
                      isRequired: isRequired,
                      isEnabled: isEnabled,
                      fieldOrder: field?.fieldOrder ?? 0,
                      options: options,
                      createdAt: field?.createdAt ?? DateTime.now(),
                    );

                    if (field == null) {
                      await _repository.createField(
                        newField,
                      );
                    } else {
                      await _repository.updateField(
                        newField,
                      );
                    }

                    if (!context.mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                    );

                    await _loadFields();
                  },
                  child: const Text(
                    'ذخیره',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    optionsController.dispose();
  }

  // =========================================================
  // TOGGLE ENABLE
  // =========================================================

  Future<void> _toggleField(
    CustomField field,
  ) async {
    if (field.fieldId == null) {
      return;
    }

    await _repository.setFieldEnabled(
      field.fieldId!,
      !field.isEnabled,
    );

    await _loadFields();
  }

  // =========================================================
  // ARCHIVE
  // =========================================================

  Future<void> _archiveField(
    CustomField field,
  ) async {
    if (field.fieldId == null) {
      return;
    }

    await _repository.archiveField(
      field.fieldId!,
    );

    await _loadFields();
  }

  // =========================================================
  // FIELD ICON
  // =========================================================

  IconData _fieldIcon(
    CustomFieldType type,
  ) {
    switch (type) {
      case CustomFieldType.text:
        return Icons.text_fields;

      case CustomFieldType.number:
        return Icons.numbers;

      case CustomFieldType.percentage:
        return Icons.percent;

      case CustomFieldType.money:
        return Icons.attach_money;

      case CustomFieldType.boolean:
        return Icons.toggle_on;

      case CustomFieldType.date:
        return Icons.calendar_today;

      case CustomFieldType.dropdown:
        return Icons.arrow_drop_down_circle;
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'فیلدهای سفارشی',
        ),
        actions: [
          IconButton(
            tooltip: 'تنظیمات رنگ',
            icon: const Icon(
              Icons.palette_outlined,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ColorSettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showFieldDialog();
        },
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'فیلد جدید',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.language),
                label: const Text('دسترسی سریع به سایت‌ها'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const QuickWebsitesPage(),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: _fields.isEmpty
                ? const Center(
                    child: Text('هنوز فیلدی ایجاد نشده است.'),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFields,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(
                        top: 12,
                        left: 12,
                        right: 12,
                        bottom: 100,
                      ),
                      itemCount: _fields.length,
                      itemBuilder: (context, index) {
                        final field = _fields[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(_fieldIcon(field.fieldType)),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(field.fieldName),
                                ),
                                if (field.isRequired)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Text(
                                      '*',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('دسته: ${field.category}'),
                                  Text(
                                    '${field.typeName} • '
                                    '${field.isRequired ? 'اجباری' : 'اختیاری'} • '
                                    '${field.isEnabled ? 'فعال' : 'غیرفعال'}',
                                  ),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'edit':
                                    await _showFieldDialog(field: field);
                                    break;
                                  case 'toggle':
                                    await _toggleField(field);
                                    break;
                                  case 'archive':
                                    await _archiveField(field);
                                    break;
                                }
                              },
                              itemBuilder: (context) {
                                return [
                                  const PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Text('ویرایش'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'toggle',
                                    child: Text(
                                      field.isEnabled
                                          ? 'غیرفعال کردن'
                                          : 'فعال کردن',
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'archive',
                                    child: Text('بایگانی'),
                                  ),
                                ];
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
