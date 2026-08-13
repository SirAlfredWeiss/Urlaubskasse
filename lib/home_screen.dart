import 'package:flutter/material.dart';

import 'models.dart';
import 'split_utils.dart';
import 'supabase_service.dart';

Color colorOf(Person? p) {
  final hex = p?.color;
  if (hex == null) return const Color(0xFF8A94A6);
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF8A94A6) : Color(v);
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  return parts.take(2).map((w) => w[0].toUpperCase()).join();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = UrlaubskasseService();

  List<Trip> _trips = [];
  Trip? _trip;
  List<Person> _persons = [];
  List<Expense> _expenses = [];

  bool _loading = true;
  String? _error;
  int _tab = 0;

  Person? personById(String id) {
    for (final p in _persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await _service.fetchTrips();
      _trips = trips;
      _trip = trips.isNotEmpty ? trips.first : null;
      if (_trip != null) {
        await _loadTripData();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadTripData() async {
    if (_trip == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final persons = await _service.fetchPersons(_trip!.id);
      final expenses = await _service.fetchExpenses(_trip!.id);
      setState(() {
        _persons = persons;
        _expenses = expenses;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAddForm() async {
    if (_trip == null || _persons.isEmpty) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExpenseSheet(
        persons: _persons,
        onSave: (data) => _service.addExpense(
          tripId: _trip!.id,
          spentBy: data.spentBy,
          amount: data.amount,
          description: data.description,
          expenseDate: data.expenseDate,
          splitMethod: data.splitMethod,
          participants: data.participants,
        ),
      ),
    );
    if (added == true) await _loadTripData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _trips.length > 1
            ? DropdownButton<Trip>(
                value: _trip,
                underline: const SizedBox.shrink(),
                items: _trips
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (t) {
                  if (t == null) return;
                  setState(() => _trip = t);
                  _loadTripData();
                },
              )
            : Text(_trip?.name ?? 'Urlaubskasse'),
      ),
      body: _buildBody(),
      floatingActionButton: (!_loading && _tab == 0 && _persons.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _openAddForm,
              icon: const Icon(Icons.add),
              label: const Text('Ausgabe'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Ausgaben'),
          NavigationDestination(
              icon: Icon(Icons.balance_outlined),
              selectedIcon: Icon(Icons.balance),
              label: 'Abrechnung'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _loadTrips);
    }
    if (_trip == null) {
      return const Center(child: Text('Keine Reise gefunden.'));
    }
    return RefreshIndicator(
      onRefresh: _loadTripData,
      child: _tab == 0 ? _expensesView() : _settlementView(),
    );
  }

  Widget _expensesView() {
    if (_expenses.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Noch keine Ausgaben.')),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: _expenses.length,
      itemBuilder: (_, i) {
        final e = _expenses[i];
        final payer = personById(e.spentBy);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.description.isEmpty ? 'Ausgabe' : e.description,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ),
                    Text(euro(e.amount),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (e.expenseDate != null)
                      Text('${dateLabel(e.expenseDate)}  ·  ',
                          style: TextStyle(color: Colors.grey[600])),
                    _Avatar(person: payer, size: 20),
                    const SizedBox(width: 6),
                    Text('bezahlt von ${payer?.name ?? '?'}',
                        style: TextStyle(color: Colors.grey[700])),
                  ],
                ),
                if (e.participants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: e.participants.map((pt) {
                      final person = personById(pt.personId);
                      return Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: _Avatar(person: person, size: 18),
                        label: Text(person?.name ?? '?'),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settlementView() {
    final balances = computeBalances(_persons, _expenses);
    final transfers = computeSettlement(_persons, _expenses);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text('Stand pro Person',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Card(
          child: Column(
            children: balances.map((b) {
              final pos = b.net >= 0;
              return ListTile(
                leading: _Avatar(person: b.person, size: 34),
                title: Text(b.person.name),
                trailing: Text(
                  '${pos ? '+' : ''}${euro(b.net)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: pos
                        ? const Color(0xFF0E7C86)
                        : const Color(0xFFE8663D),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text('Ausgleich',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Card(
          child: transfers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Alles ausgeglichen ✓')),
                )
              : Column(
                  children: transfers.map((t) {
                    return ListTile(
                      leading: _Avatar(person: t.from, size: 30),
                      title: Row(
                        children: [
                          Flexible(child: Text(t.from.name)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, size: 16),
                          ),
                          Flexible(child: Text(t.to.name)),
                        ],
                      ),
                      trailing: Text(euro(t.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final Person? person;
  final double size;
  const _Avatar({required this.person, required this.size});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colorOf(person),
      child: Text(
        initials(person?.name ?? '?'),
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Konnte Daten nicht laden.',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Erneut')),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class NewExpense {
  final String spentBy;
  final double amount;
  final String description;
  final String expenseDate;
  final String splitMethod;
  final List<Map<String, dynamic>> participants;
  NewExpense({
    required this.spentBy,
    required this.amount,
    required this.description,
    required this.expenseDate,
    required this.splitMethod,
    required this.participants,
  });
}

class AddExpenseSheet extends StatefulWidget {
  final List<Person> persons;
  final Future<void> Function(NewExpense) onSave;
  const AddExpenseSheet({super.key, required this.persons, required this.onSave});

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  final Map<String, TextEditingController> _shares = {};

  Person? _payer;
  DateTime _date = DateTime.now();
  String _method = 'equal';
  final Set<String> _selected = {};
  bool _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    if (widget.persons.isNotEmpty) _payer = widget.persons.first;
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final c in _shares.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _shareCtrl(String id) =>
      _shares.putIfAbsent(id, () => TextEditingController(text: '1'));

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final desc = _desc.text.trim();
    final amount =
        double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
    if (desc.isEmpty || amount <= 0) {
      setState(() => _msg = 'Bitte Zweck und einen gueltigen Betrag angeben.');
      return;
    }
    if (_payer == null || _selected.isEmpty) {
      setState(() => _msg = 'Bitte Zahler und Beteiligte waehlen.');
      return;
    }
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final participants = _selected.map((id) {
        double? share;
        if (_method != 'equal') {
          share = double.tryParse(_shareCtrl(id).text.trim().replaceAll(',', '.'));
        }
        return {'person_id': id, 'share': share};
      }).toList();

      await widget.onSave(NewExpense(
        spentBy: _payer!.id,
        amount: amount,
        description: desc,
        expenseDate: _fmtDate(_date),
        splitMethod: _method,
        participants: participants,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _msg = 'Fehler: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Neue Ausgabe',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                  labelText: 'Wofuer?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Betrag (€)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(dateLabel(_fmtDate(_date))),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Person>(
              value: _payer,
              decoration: const InputDecoration(
                  labelText: 'Bezahlt von', border: OutlineInputBorder()),
              items: widget.persons
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (p) => setState(() => _payer = p),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Beteiligt',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(widget.persons.map((p) => p.id));
                  }),
                  child: const Text('alle'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.persons.map((p) {
                final sel = _selected.contains(p.id);
                return FilterChip(
                  avatar: _Avatar(person: p, size: 18),
                  label: Text(p.name),
                  selected: sel,
                  onSelected: (v) => setState(() {
                    v ? _selected.add(p.id) : _selected.remove(p.id);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(
                  labelText: 'Aufteilung', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'equal', child: Text('gleichmaessig teilen')),
                DropdownMenuItem(
                    value: 'shares', child: Text('nach Anteilen (Gewichte)')),
                DropdownMenuItem(
                    value: 'exact', child: Text('feste Betraege')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'equal'),
            ),
            if (_method != 'equal' && _selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._selected.map((id) {
                final person = widget.persons.firstWhere((p) => p.id == id);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(person.name)),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _shareCtrl(id),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixText: _method == 'exact' ? '€' : 'x',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (_msg != null) ...[
              const SizedBox(height: 12),
              Text(_msg!, style: const TextStyle(color: Color(0xFFB23A16))),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(_saving ? 'Speichere…' : 'Ausgabe speichern'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
