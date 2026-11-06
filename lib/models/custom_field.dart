enum CustomFieldType {
  text,
  number,
  percentage,
  money,
  boolean,
  date,
  dropdown,
}

class CustomField {
  final int? fieldId;
  final String fieldName;
  final CustomFieldType fieldType;

  // =========================================================
  // CATEGORY
  // =========================================================

  final String category;

  final bool isRequired;
  final bool isEnabled;
  final int fieldOrder;
  final List<String> options;
  final DateTime createdAt;

  const CustomField({
    this.fieldId,
    required this.fieldName,
    required this.fieldType,
    this.category = 'عمومی',
    this.isRequired = false,
    this.isEnabled = true,
    this.fieldOrder = 0,
    this.options = const [],
    required this.createdAt,
  });

  CustomField copyWith({
    int? fieldId,
    String? fieldName,
    CustomFieldType? fieldType,
    String? category,
    bool? isRequired,
    bool? isEnabled,
    int? fieldOrder,
    List<String>? options,
    DateTime? createdAt,
  }) {
    return CustomField(
      fieldId: fieldId ?? this.fieldId,
      fieldName: fieldName ?? this.fieldName,
      fieldType: fieldType ?? this.fieldType,
      category: category ?? this.category,
      isRequired: isRequired ?? this.isRequired,
      isEnabled: isEnabled ?? this.isEnabled,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      options: options ?? this.options,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // =========================================================
  // TYPE NAME
  // =========================================================

  String get typeName {
    switch (fieldType) {
      case CustomFieldType.text:
        return 'متن';

      case CustomFieldType.number:
        return 'عدد';

      case CustomFieldType.percentage:
        return 'درصد';

      case CustomFieldType.money:
        return 'مبلغ';

      case CustomFieldType.boolean:
        return 'بله / خیر';

      case CustomFieldType.date:
        return 'تاریخ';

      case CustomFieldType.dropdown:
        return 'لیست انتخابی';
    }
  }

  // =========================================================
  // TYPE KEY
  // =========================================================

  String get typeKey {
    return fieldType.name;
  }

  // =========================================================
  // TO MAP
  // =========================================================

  Map<String, dynamic> toMap() {
    return {
      'field_id': fieldId,
      'field_name': fieldName,
      'field_type': fieldType.name,
      'category': category,
      'is_required': isRequired ? 1 : 0,
      'is_enabled': isEnabled ? 1 : 0,
      'field_order': fieldOrder,
      'options_text': options.join('\n'),
      'created_at': createdAt.toIso8601String(),
    };
  }

  // =========================================================
  // FROM MAP
  // =========================================================

  factory CustomField.fromMap(
    Map<String, dynamic> map,
  ) {
    final optionsText = map['options_text']?.toString() ?? '';

    final options = optionsText
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    return CustomField(
      fieldId: map['field_id'] is int
          ? map['field_id'] as int
          : int.tryParse(
              map['field_id']?.toString() ?? '',
            ),

      fieldName: map['field_name']?.toString() ?? '',

      fieldType: _fieldTypeFromString(
        map['field_type']?.toString(),
      ),

      // اگر دسته‌بندی وجود نداشته باشد،
      // به صورت خودکار عمومی در نظر گرفته می‌شود.
      category: map['category']?.toString().trim().isNotEmpty == true
          ? map['category'].toString()
          : 'عمومی',

      isRequired: map['is_required'] == 1 || map['is_required'] == true,

      isEnabled: map['is_enabled'] == 1 || map['is_enabled'] == true,

      fieldOrder: map['field_order'] is int
          ? map['field_order'] as int
          : int.tryParse(
                map['field_order']?.toString() ?? '',
              ) ??
              0,

      options: options,

      createdAt: DateTime.tryParse(
            map['created_at']?.toString() ?? '',
          ) ??
          DateTime.now(),
    );
  }

  // =========================================================
  // FIELD TYPE FROM STRING
  // =========================================================

  static CustomFieldType _fieldTypeFromString(
    String? value,
  ) {
    switch (value) {
      case 'number':
        return CustomFieldType.number;

      case 'percentage':
        return CustomFieldType.percentage;

      case 'money':
        return CustomFieldType.money;

      case 'boolean':
        return CustomFieldType.boolean;

      case 'date':
        return CustomFieldType.date;

      case 'dropdown':
        return CustomFieldType.dropdown;

      case 'text':
      default:
        return CustomFieldType.text;
    }
  }
}
