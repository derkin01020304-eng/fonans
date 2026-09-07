import 'package:flutter/material.dart';
import '../core/money.dart';
import 'providers.dart';

enum InputKind { text, money, number, date, dateTime, choice, toggle, secret }

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = InputKind.text,
    this.initial = '',
    this.required = true,
    this.choices = const {},
    this.hint,
    this.allowNegative = false,
  });
  final String key, label;
  final InputKind kind;
  final Object initial;
  final bool required, allowNegative;
  final Map<String, String> choices;
  final String? hint;
}

Future<void> showEditor(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  required Future<void> Function(Map<String, dynamic>) onSave,
  String? note,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) =>
      EditorSheet(title: title, fields: fields, onSave: onSave, note: note),
);

class EditorSheet extends StatefulWidget {
  const EditorSheet({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.note,
  });
  final String title;
  final List<FieldSpec> fields;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final String? note;
  @override
  State<EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<EditorSheet> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _values[f.key] = f.initial;
      _controllers[f.key] = TextEditingController(text: f.initial.toString());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = Map<String, dynamic>.from(_values);
      for (final f in widget.fields) {
        if ([
          InputKind.text,
          InputKind.money,
          InputKind.number,
          InputKind.secret,
        ].contains(f.kind)) {
          values[f.key] = _controllers[f.key]!.text.trim();
        }
      }
      await widget.onSave(values);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (widget.note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      widget.note!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _field(f),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_busy ? 'Сохранение…' : 'Сохранить'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _field(FieldSpec f) {
    if (f.kind == InputKind.choice) {
      return DropdownButtonFormField<String>(
        initialValue: _values[f.key] as String,
        isExpanded: true,
        decoration: InputDecoration(labelText: f.label),
        items: f.choices.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v),
      );
    }
    if (f.kind == InputKind.toggle) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: _values[f.key] as bool,
        onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v),
      );
    }
    if (f.kind == InputKind.date || f.kind == InputKind.dateTime) {
      final value = _values[f.key] as DateTime;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(f.label),
        subtitle: Text(
          dateLabel(value) +
              (f.kind == InputKind.dateTime
                  ? ' • ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'
                  : ''),
        ),
        trailing: const Icon(Icons.calendar_today_outlined),
        onTap: _busy
            ? null
            : () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: value,
                  firstDate: DateTime(1970),
                  lastDate: DateTime(2100),
                );
                if (selected == null || !mounted) return;
                var result = selected;
                if (f.kind == InputKind.dateTime) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(value),
                  );
                  if (time == null || !mounted) return;
                  result = DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    time.hour,
                    time.minute,
                  );
                }
                setState(() => _values[f.key] = result);
              },
      );
    }
    return TextFormField(
      controller: _controllers[f.key],
      enabled: !_busy,
      obscureText: f.kind == InputKind.secret,
      autocorrect: f.kind != InputKind.secret,
      enableSuggestions: f.kind != InputKind.secret,
      maxLines: f.kind == InputKind.secret ? 1 : null,
      keyboardType: [InputKind.money, InputKind.number].contains(f.kind)
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: f.label, hintText: f.hint),
      validator: (v) {
        if (f.required && (v == null || v.trim().isEmpty))
          return 'Заполните поле';
        if (v == null || v.isEmpty) return null;
        if (f.kind == InputKind.money) {
          try {
            parseMoney(v, allowNegative: f.allowNegative);
          } catch (e) {
            return errorText(e);
          }
        }
        if (f.kind == InputKind.number &&
            double.tryParse(v.replaceAll(',', '.')) == null)
          return 'Введите число';
        return null;
      },
    );
  }
}
