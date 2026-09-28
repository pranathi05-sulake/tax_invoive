import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../services/validation/invoice_validator.dart';
import '../services/database/database_helper.dart';
import '../services/invoice_sync_service.dart';
import '../config/api_config.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final Invoice? invoice;
  final bool isEditingInitially;

  const InvoiceDetailScreen({
    super.key,
    this.invoice,
    this.isEditingInitially = false,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _formKey = GlobalKey<FormState>();

  late bool _isEditing;
  late String _id;
  late TextEditingController _vendorController;
  late TextEditingController _gstinController;
  late TextEditingController _invoiceNoController;
  late TextEditingController _cgstController;
  late TextEditingController _sgstController;
  late TextEditingController _igstController;
  late DateTime _selectedDate;
  late InvoiceStatus _selectedStatus;
  late List<_EditableItem> _editableItems;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.isEditingInitially || widget.invoice == null;
    final inv = widget.invoice;

    _id = inv?.id ?? 'inv-${DateTime.now().millisecondsSinceEpoch}';
    _vendorController = TextEditingController(text: inv?.vendorName ?? '');
    _gstinController = TextEditingController(text: inv?.gstin ?? '');
    _invoiceNoController = TextEditingController(text: inv?.invoiceNumber ?? '');
    _cgstController = TextEditingController(
        text: inv != null && inv.cgst > 0 ? inv.cgst.toStringAsFixed(2) : '0.00');
    _sgstController = TextEditingController(
        text: inv != null && inv.sgst > 0 ? inv.sgst.toStringAsFixed(2) : '0.00');
    _igstController = TextEditingController(
        text: inv != null && inv.igst > 0 ? inv.igst.toStringAsFixed(2) : '0.00');
    _selectedDate = inv?.date ?? DateTime.now();
    _selectedStatus = inv?.status ?? InvoiceStatus.verified;

    if (inv != null && inv.items.isNotEmpty) {
      _editableItems = inv.items
          .map((item) => _EditableItem(
                id: item.id,
                descController: TextEditingController(text: item.description),
                qtyController:
                    TextEditingController(text: item.quantity.toString()),
                priceController: TextEditingController(
                    text: item.unitPrice.toStringAsFixed(2)),
              ))
          .toList();
    } else {
      _editableItems = [
        _EditableItem(
          id: 'item-1',
          descController: TextEditingController(text: 'Consulting / Products'),
          qtyController: TextEditingController(text: '1'),
          priceController: TextEditingController(text: '1000.00'),
        ),
      ];
    }
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _gstinController.dispose();
    _invoiceNoController.dispose();
    _cgstController.dispose();
    _sgstController.dispose();
    _igstController.dispose();
    for (final item in _editableItems) {
      item.dispose();
    }
    super.dispose();
  }

  double get _computedSubtotal {
    double sub = 0.0;
    for (final item in _editableItems) {
      final qty = int.tryParse(item.qtyController.text) ?? 0;
      final price = double.tryParse(item.priceController.text) ?? 0.0;
      sub += (qty * price);
    }
    return sub;
  }

  double get _computedCgst => double.tryParse(_cgstController.text) ?? 0.0;
  double get _computedSgst => double.tryParse(_sgstController.text) ?? 0.0;
  double get _computedIgst => double.tryParse(_igstController.text) ?? 0.0;
  double get _computedTotal =>
      _computedSubtotal + _computedCgst + _computedSgst + _computedIgst;

  void _addItem() {
    setState(() {
      _editableItems.add(_EditableItem(
        id: 'item-${DateTime.now().millisecondsSinceEpoch}',
        descController: TextEditingController(text: ''),
        qtyController: TextEditingController(text: '1'),
        priceController: TextEditingController(text: '0.00'),
      ));
    });
  }

  void _removeItem(int index) {
    if (_editableItems.length > 1) {
      setState(() {
        final item = _editableItems.removeAt(index);
        item.dispose();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one item is required.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveInvoice() async {
    debugPrint('[InvoiceSave] BUTTON PRESSED');

    // 1. Form Validation Check
    debugPrint('[InvoiceSave] VALIDATION START');
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Form validation error. Please fill required fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 2. Build Invoice from current controllers & state
    debugPrint('[InvoiceSave] BUILDING INVOICE');
    final items = _editableItems.map((e) {
      final qty = int.tryParse(e.qtyController.text) ?? 1;
      final price = double.tryParse(e.priceController.text) ?? 0.0;
      return InvoiceItem(
        id: e.id,
        description: e.descController.text.trim(),
        quantity: qty,
        unitPrice: price,
      );
    }).toList();

    final updatedInvoice = Invoice(
      id: _id,
      vendorName: _vendorController.text.trim(),
      gstin: _gstinController.text.trim().toUpperCase(),
      invoiceNumber: _invoiceNoController.text.trim(),
      date: _selectedDate,
      subtotal: _computedSubtotal,
      cgst: _computedCgst,
      sgst: _computedSgst,
      igst: _computedIgst,
      status: _selectedStatus,
      items: items,
    );

    // 3. Invoice Validator Check
    final validationResult = InvoiceValidator.validate(updatedInvoice);
    if (!validationResult.isValid) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Text('Validation Warnings'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The following issues were found:'),
              const SizedBox(height: 10),
              ...validationResult.warnings.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(w)),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              const Text('Do you want to save anyway?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );

      if (proceed != true) {
        return;
      }
    }

    debugPrint('[InvoiceSave] VALIDATION PASSED');
    debugPrint('[InvoiceSave] DUPLICATE CHECK');
    debugPrint('[InvoiceSave] DATABASE SAVE START');

    try {
      final savedInvoice = await DatabaseHelper.instance.insertInvoice(updatedInvoice);

      if (!mounted) return;

      if (savedInvoice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Duplicate invoice detected'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      debugPrint('[InvoiceSave] DATABASE SAVE SUCCESS');

      if (updatedInvoice.status == InvoiceStatus.verified) {
        InvoiceSyncService().syncInvoice(updatedInvoice).then((res) {
          debugPrint('[InvoiceSave] Auto LAN sync result: ${res.status}');
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(updatedInvoice.status == InvoiceStatus.verified
                  ? 'Invoice saved & queued for LAN sync'
                  : 'Invoice saved successfully'),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      if (widget.invoice == null) {
        Navigator.pop(context, updatedInvoice);
      } else {
        setState(() {
          _isEditing = false;
        });
        Navigator.pop(context, updatedInvoice);
      }
    } catch (e) {
      debugPrint('[InvoiceSave] DATABASE SAVE ERROR');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to save invoice. Please try again.'),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.invoice == null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final currentInvoice = Invoice(
          id: _id,
          vendorName: _vendorController.text.trim(),
          gstin: _gstinController.text.trim(),
          invoiceNumber: _invoiceNoController.text.trim(),
          date: _selectedDate,
          subtotal: _computedSubtotal,
          cgst: _computedCgst,
          sgst: _computedSgst,
          igst: _computedIgst,
          status: _selectedStatus,
          items: _editableItems.map((e) {
            return InvoiceItem(
              id: e.id,
              description: e.descController.text.trim(),
              quantity: int.tryParse(e.qtyController.text) ?? 1,
              unitPrice: double.tryParse(e.priceController.text) ?? 0.0,
            );
          }).toList(),
        );
        Navigator.pop(context, currentInvoice);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            isNew
                ? 'New Invoice'
                : _isEditing
                    ? 'Edit Invoice'
                    : 'Invoice Details',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: [
            if (!_isEditing && !isNew) ...[
              IconButton(
                tooltip: 'Edit Invoice',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  setState(() {
                    _isEditing = true;
                  });
                },
              ),
              PopupMenuButton<InvoiceStatus>(
                tooltip: 'Change Status',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (status) {
                  setState(() {
                    _selectedStatus = status;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Status changed to ${status.name.toUpperCase()}'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: InvoiceStatus.verified,
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
                        SizedBox(width: 8),
                        Text('Mark as Verified'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: InvoiceStatus.pending,
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_empty, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 8),
                        Text('Mark as Pending'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: InvoiceStatus.flagged,
                    child: Row(
                      children: [
                        Icon(Icons.flag_rounded, color: Color(0xFFDC2626), size: 18),
                        SizedBox(width: 8),
                        Text('Flag for Review'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (_isEditing)
              IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.check_rounded),
                onPressed: _saveInvoice,
              ),
          ],
        ),
        body: _isEditing ? _buildEditForm(theme) : _buildViewMode(theme),
      ),
    );
  }

  Widget _buildViewMode(ThemeData theme) {
    final statusColor = _selectedStatus == InvoiceStatus.verified
        ? const Color(0xFF059669)
        : _selectedStatus == InvoiceStatus.pending
            ? const Color(0xFFD97706)
            : const Color(0xFFDC2626);

    final statusBg = _selectedStatus == InvoiceStatus.verified
        ? const Color(0xFFECFDF5)
        : _selectedStatus == InvoiceStatus.pending
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFFEF2F2);

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final formattedDate =
        '${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.invoice != null && _selectedStatus == InvoiceStatus.verified) ...[
            _buildLanSyncCard(context, widget.invoice!),
            const SizedBox(height: 16),
          ],
          // Vendor Card
          Container(
            padding: const EdgeInsets.all(18.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _vendorController.text.isNotEmpty
                            ? _vendorController.text.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vendorController.text.isEmpty
                                ? 'Not detected'
                                : _vendorController.text,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _vendorController.text.isEmpty ? Colors.red[800] : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'GSTIN: ${_gstinController.text.isEmpty ? 'Not detected' : _gstinController.text}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _gstinController.text.isEmpty ? Colors.red[800] : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _selectedStatus.name.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Invoice Number',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _invoiceNoController.text.isEmpty
                              ? 'Not detected'
                              : _invoiceNoController.text,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _invoiceNoController.text.isEmpty ? Colors.red[800] : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Date',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Line Items Table
          Text(
            'Line Items (${_editableItems.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _editableItems.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final item = _editableItems[index];
                final qty = int.tryParse(item.qtyController.text) ?? 1;
                final price = double.tryParse(item.priceController.text) ?? 0.0;
                final lineTotal = qty * price;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 14.0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.descController.text.isEmpty
                                  ? 'Item ${index + 1}'
                                  : item.descController.text,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$qty × ₹${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${lineTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Tax & Total Summary Card
          Text(
            'Tax Breakdown',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildSummaryRow('Subtotal', '₹${_computedSubtotal.toStringAsFixed(2)}'),
                if (_computedCgst > 0) ...[
                  const SizedBox(height: 10),
                  _buildSummaryRow('CGST', '₹${_computedCgst.toStringAsFixed(2)}'),
                ],
                if (_computedSgst > 0) ...[
                  const SizedBox(height: 10),
                  _buildSummaryRow('SGST', '₹${_computedSgst.toStringAsFixed(2)}'),
                ],
                if (_computedIgst > 0) ...[
                  const SizedBox(height: 10),
                  _buildSummaryRow('IGST', '₹${_computedIgst.toStringAsFixed(2)}'),
                ],
                const SizedBox(height: 10),
                _buildSummaryRow(
                  'Total Tax Tracked',
                  '₹${(_computedCgst + _computedSgst + _computedIgst).toStringAsFixed(2)}',
                  isAccent: true,
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Payable',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      '₹${_computedTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Offline Security Notice
          Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded, size: 20, color: Color(0xFF059669)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Stored safely in local offline storage. Ready for offline tax deduction logs.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEditForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vendor Details Section
            Text(
              'Vendor & Invoice Info',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _vendorController,
              decoration: _inputDecoration('Vendor Name', Icons.business_rounded),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter vendor name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _gstinController,
              decoration: _inputDecoration('GSTIN / Tax ID', Icons.badge_outlined),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _invoiceNoController,
                    decoration:
                        _inputDecoration('Invoice Number', Icons.tag_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter invoice number'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Verification Status
            Text(
              'Verification Status',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: InvoiceStatus.values.map((status) {
                final isSelected = _selectedStatus == status;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(status.name.toUpperCase()),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedStatus = status;
                          });
                        }
                      },
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Line Items Editor
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Itemized Products / Services',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            ..._editableItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: item.descController,
                            decoration: _inputDecoration(
                              'Item Description',
                              Icons.shopping_bag_outlined,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ),
                        if (_editableItems.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Color(0xFFEF4444)),
                            onPressed: () => _removeItem(idx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: item.qtyController,
                            keyboardType: TextInputType.number,
                            decoration:
                                _inputDecoration('Quantity', Icons.numbers),
                            onChanged: (_) => setState(() {}),
                            validator: (v) => (int.tryParse(v ?? '') == null)
                                ? 'Invalid'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: item.priceController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: _inputDecoration(
                                'Unit Rate (₹)', Icons.currency_rupee),
                            onChanged: (_) => setState(() {}),
                            validator: (v) =>
                                (double.tryParse(v ?? '') == null)
                                    ? 'Invalid'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            // Tax Breakdown inputs
            Text(
              'Tax Calculations (₹)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cgstController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration('CGST', Icons.percent),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _sgstController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration('SGST', Icons.percent),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _igstController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration('IGST', Icons.percent),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Live Totals Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Payable (Live)',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${_computedTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _saveInvoice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Save Invoice'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isAccent = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isAccent ? const Color(0xFF059669) : const Color(0xFF64748B),
            fontSize: 14,
            fontWeight: isAccent ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isAccent ? const Color(0xFF059669) : const Color(0xFF0F172A),
            fontSize: 14,
            fontWeight: isAccent ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLanSyncCard(BuildContext context, Invoice invoice) {
    bool isSyncing = invoice.syncStatus == SyncStatus.syncing;
    bool isSynced = invoice.syncStatus == SyncStatus.synced;
    bool isFailed = invoice.syncStatus == SyncStatus.syncFailed;

    Color badgeBg = isSynced
        ? const Color(0xFFF0FDF4)
        : isFailed
            ? const Color(0xFFFEF2F2)
            : isSyncing
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFFFFBEB);

    Color badgeFg = isSynced
        ? const Color(0xFF166534)
        : isFailed
            ? const Color(0xFF991B1B)
            : isSyncing
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFB45309);

    String statusLabel = isSynced
        ? 'Synced to Company LAN'
        : isFailed
            ? 'LAN Sync Failed'
            : isSyncing
                ? 'Syncing to LAN...'
                : 'Pending LAN Sync';

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isSynced
                        ? Icons.cloud_done_rounded
                        : isFailed
                            ? Icons.cloud_off_rounded
                            : isSyncing
                                ? Icons.sync_rounded
                                : Icons.cloud_upload_outlined,
                    color: badgeFg,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Company LAN Sync',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: badgeFg,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (invoice.serverInvoiceId != null && invoice.serverInvoiceId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Server ID: ${invoice.serverInvoiceId}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontFamily: 'monospace'),
            ),
          ],
          if (invoice.lastSyncError != null && invoice.lastSyncError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Error: ${invoice.lastSyncError}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              icon: isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                    )
                  : Icon(
                      isSynced ? Icons.refresh_rounded : Icons.cloud_upload_rounded,
                      size: 16,
                    ),
              label: Text(
                isSyncing
                    ? 'Syncing...'
                    : isSynced
                        ? 'Re-sync to LAN'
                        : 'Sync Now to LAN',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: isSyncing
                  ? null
                  : () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Attempting LAN synchronization...'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      final res = await InvoiceSyncService().syncInvoice(invoice);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res.success
                              ? 'LAN Sync successful! Status: ${res.status.name}'
                              : 'LAN Sync issue: ${res.errorMessage}'),
                          backgroundColor: res.success ? const Color(0xFF059669) : Colors.red[800],
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      setState(() {});
                    },
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableItem {
  final String id;
  final TextEditingController descController;
  final TextEditingController qtyController;
  final TextEditingController priceController;

  _EditableItem({
    required this.id,
    required this.descController,
    required this.qtyController,
    required this.priceController,
  });

  void dispose() {
    descController.dispose();
    qtyController.dispose();
    priceController.dispose();
  }
}
