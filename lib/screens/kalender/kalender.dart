import 'package:flutter/material.dart';
import 'package:nami/screens/mitgliedsliste/mitglied_details.dart';
import 'package:nami/services/member_service.dart';
import 'package:nami/utilities/hive/custom_group.dart';
import 'package:nami/utilities/hive/mitglied.dart';
import 'package:nami/utilities/mitglied.filterAndSort.dart';
import 'package:nami/utilities/stufe.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

/// Kalender-Ansicht mit Geburtstagen und Filterleiste –
/// mit Pill-Toggle (Tabellenansicht ↔ Agenda),
/// Agenda "Springe zu Datum" + Fenster 1 Jahr ab Ankerdatum,
/// farbige Marker je Stufe (über stufe.farbe).
class KalenderScreen extends StatefulWidget {
  const KalenderScreen({super.key});

  @override
  State<KalenderScreen> createState() => _KalenderScreenState();
}

enum _ViewMode { tabelle, agenda }

class _KalenderScreenState extends State<KalenderScreen> {
  final MemberService _memberService = HiveMemberService();
  late final MemberListSettingsHandler _settings = MemberListSettingsHandler();

  List<Mitglied> _all = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// Tag -> Geburtstagskinder im aktuell angezeigten Jahr
  final Map<DateTime, List<Mitglied>> _events = <DateTime, List<Mitglied>>{};

  CalendarFormat _calendarFormat = CalendarFormat.month;
  int _eventsYear = DateTime.now().year;
  _ViewMode _mode = _ViewMode.tabelle; // Start wie bisher

  // Agenda: 1-Jahresfenster ab Ankerdatum + Scroll-Keys
  DateTime _agendaAnchor = _atMidnight(DateTime.now());
  final _agendaSectionKeys = <DateTime, GlobalKey>{};
  final _agendaScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _settings.dispose();
    _agendaScrollController.dispose();
    super.dispose();
  }

  void _loadMembers() {
    final list = _memberService.getAllMembers();
    if (!mounted) return;
    setState(() => _all = list);
    _rebuildEventsForYear(_eventsYear);
  }

  // ----------------- Helper -----------------

  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  DateTime? _mapBirthdayToYear(DateTime? geburtsDatum, int year) {
    if (geburtsDatum == null) return null;
    final int month = geburtsDatum.month;
    final int day = geburtsDatum.day;
    if (month == 2 && day == 29) {
      final bool isLeap = _isLeapYear(year);
      return _dayKey(DateTime(year, 2, isLeap ? 29 : 28));
    }
    return _dayKey(DateTime(year, month, day));
  }

  bool _isLeapYear(int year) =>
      (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0));

  void _rebuildEventsForYear(int year) {
    if (!mounted) return;
    _events.clear();

    final filtered = _applyActiveGroupsFilter(_all);
    for (final m in filtered) {
      final dt = _mapBirthdayToYear(m.geburtsDatum, year);
      if (dt == null) continue;
      _events.putIfAbsent(dt, () => <Mitglied>[]).add(m);
    }
    setState(() {});
  }

  String _currentTaetigkeitOf(Mitglied m) {
    try {
      final active = m.getActiveTaetigkeiten();
      if (active.isNotEmpty) {
        final a = active.first;
        try {
          final label =
              (a as dynamic).taetigkeit ??
              (a as dynamic).bezeichnung ??
              (a as dynamic).name;
          if (label is String) return label;
        } catch (_) {}
        return a.toString();
      }
    } catch (_) {}
    return '';
  }

  int? _ageOnDate(DateTime? birthDate, DateTime onDate) {
    if (birthDate == null) return null;
    int age = onDate.year - birthDate.year;
    final hadBirthday =
        (onDate.month > birthDate.month) ||
        (onDate.month == birthDate.month && onDate.day >= birthDate.day);
    if (!hadBirthday) age -= 1;
    return age;
  }

  void _openMitgliedDetails(Mitglied m) {
    try {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => MitgliedDetail(mitglied: m)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Details konnten nicht geöffnet werden: $e')),
      );
    }
  }

  // ----------------- Filtering (OR zwischen aktiven Gruppen) -----------------

  List<Mitglied> _applyActiveGroupsFilter(List<Mitglied> input) {
    final Map<String, CustomGroup> groups = _settings.filterOptions.filterGroup;
    final List<CustomGroup> active = groups.values
        .where((g) => g.active)
        .toList();
    if (active.isEmpty) return List<Mitglied>.from(input);

    bool matches(Mitglied m, CustomGroup g) {
      final stufe = (g as dynamic).stufe;
      if (stufe != null) {
        final current = m.currentStufe;
        if (current != stufe) return false;
      }

      final List<String>? required =
          (g as dynamic).taetigkeiten as List<String>?;
      if (required != null && required.isNotEmpty) {
        final activeTaet = m.getActiveTaetigkeiten();
        bool containsNeedle(String needle) {
          return activeTaet.any((a) {
            try {
              final t =
                  (a as dynamic).taetigkeit ??
                  (a as dynamic).bezeichnung ??
                  (a as dynamic).name;
              if (t is String && t == needle) return true;
              final id = (a as dynamic).id;
              if (id != null && id.toString() == needle) return true;
            } catch (_) {}
            return false;
          });
        }

        if (!required.every(containsNeedle)) return false;
      }
      return true;
    }

    return input.where((m) => active.any((g) => matches(m, g))).toList();
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MemberListSettingsHandler>.value(
      value: _settings,
      child: Builder(
        builder: (inner) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Kalender'),
              centerTitle: true,
              actions: [
                IconButton(
                  tooltip: 'Heute / Zu Datum springen',
                  icon: const Icon(Icons.event),
                  onPressed: _showTopRightDateMenu,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Neu laden',
                  onPressed: () => _rebuildEventsForYear(_eventsYear),
                ),
              ],
            ),
            body: Column(
              children: [
                // Filter bleiben oben – unverändert
                _buildFilterGroup(),

                // Toggle darunter
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: _PillSegmentedControl(
                    leftLabel: 'Tabellenansicht',
                    rightLabel: 'Agenda',
                    isRightActive: _mode == _ViewMode.agenda,
                    onLeftTap: () => setState(() => _mode = _ViewMode.tabelle),
                    onRightTap: () {
                      setState(() {
                        _mode = _ViewMode.agenda;
                        _agendaAnchor = _atMidnight(DateTime.now());
                      });
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollAgendaTo(_agendaAnchor),
                      );
                    },
                  ),
                ),

                // Inhalt unterhalb der Filter/Toggle
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _mode == _ViewMode.tabelle
                        ? _buildCalendarView(key: const ValueKey('table'))
                        : _buildAgendaView(key: const ValueKey('agenda')),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Tabellenansicht (wie bisher) ----------
  Widget _buildCalendarView({Key? key}) {
    return Column(
      key: key,
      children: [
        Expanded(
          child: TableCalendar<Mitglied>(
            firstDay: DateTime.utc(1900, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            headerStyle: const HeaderStyle(
              titleCentered: true,
              formatButtonShowsNext: false,
              formatButtonVisible: true,
            ),
            calendarFormat: _calendarFormat,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Monat',
              CalendarFormat.twoWeeks: '2 Wochen',
              CalendarFormat.week: 'Woche',
            },
            onFormatChanged: (format) =>
                setState(() => _calendarFormat = format),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
              if (_eventsYear != focusedDay.year) {
                _eventsYear = focusedDay.year;
                _rebuildEventsForYear(_eventsYear);
              }
            },
            eventLoader: (day) => _events[_dayKey(day)] ?? const <Mitglied>[],
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                final members = events.cast<Mitglied>();
                final count = members.length;
                if (count == 0) return null;
                // Bis zu 4 farbige Punkte je Stufe; sonst Zahl.
                if (count <= 4) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 35),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: members.map((m) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: _stufeColor(m.currentStufe, context),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 34),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _buildSelectedDayList(),
      ],
    );
  }

  // ---------- Agenda-Ansicht ----------
  Widget _buildAgendaView({Key? key}) {
    // Liste aller Tage im Jahr mit Geburtstagen (nach Filtern)
    final allDates = _events.keys.toList()..sort();
    if (allDates.isEmpty) {
      return const Center(child: Text('Keine Geburtstage gefunden'));
    }

    // 1-Jahresfenster ab Ankerdatum
    final start = _agendaAnchor;
    final end = _agendaAnchor.add(const Duration(days: 365));

    final dates =
        (allDates
              ..removeWhere(
                (d) =>
                    d.isBefore(_atMidnight(start)) ||
                    d.isAfter(_atMidnight(end)),
              )
              ..sort())
            .toList();

    // Keys für ensureVisible bereitstellen
    _agendaSectionKeys.clear();
    for (final d in dates) {
      _agendaSectionKeys[d] = GlobalKey();
    }

    return Column(
      key: key,
      children: [
        //const Divider(height: 1),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              // Zu Datum springen
              OutlinedButton.icon(
                onPressed: _pickAnchorDate,
                icon: const Icon(Icons.date_range),
                label: const Text('Zu Datum springen'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _agendaScrollController,
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: dates.length,
            itemBuilder: (context, i) {
              final day = dates[i];
              final members = [...?_events[day]]
                ..sort((a, b) => a.nachname.compareTo(b.nachname));
              return Container(
                key: _agendaSectionKeys[day],
                child: _AgendaSection<Mitglied>(
                  date: day,
                  items: members,
                  itemBuilder: (m) => _AgendaBirthdayTile(
                    mitglied: m,
                    age: _ageOnDate(m.geburtsDatum, day),
                    onTap: () => _openMitgliedDetails(m),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Scroll-Helfer: zum Tag oder zur nächsten zukünftigen Sektion springen
  void _scrollAgendaTo(DateTime targetDay) {
    final dayKey = _atMidnight(targetDay);
    DateTime? target;
    for (final d in (_agendaSectionKeys.keys.toList()..sort())) {
      if (!d.isBefore(dayKey)) {
        target = d;
        break;
      }
    }
    target ??= _agendaSectionKeys.keys.isEmpty
        ? dayKey
        : (_agendaSectionKeys.keys.toList()..sort()).last;

    final key = _agendaSectionKeys[target];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.06,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickAnchorDate() async {
    final now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDate: _agendaAnchor,
      helpText: 'Springe zu Datum',
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
    );
    if (picked != null) {
      setState(() => _agendaAnchor = _atMidnight(picked));
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollAgendaTo(_agendaAnchor),
      );
    }
  }

  Future<void> _showTopRightDateMenu() async {
    final result = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 16, 0), // Rechts oben
      items: const [
        PopupMenuItem(
          value: 'today',
          child: ListTile(leading: Icon(Icons.today), title: Text('Heute')),
        ),
        PopupMenuItem(
          value: 'pick',
          child: ListTile(
            leading: Icon(Icons.calendar_today),
            title: Text('Zu Datum springen'),
          ),
        ),
      ],
    );
    if (!mounted) return; // 🔒 wichtig nach await

    if (result == 'today') {
      final now = DateTime.now();
      if (_mode == _ViewMode.tabelle) {
        setState(() {
          _focusedDay = now;
          _selectedDay = now;
        });
        if (_eventsYear != now.year) {
          _eventsYear = now.year;
          _rebuildEventsForYear(_eventsYear);
        }
      } else {
        setState(() => _agendaAnchor = _atMidnight(now));
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollAgendaTo(_agendaAnchor),
        );
      }
      return;
    }

    if (result == 'pick') {
      final now = DateTime.now();
      final DateTime? picked = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year - 10, 1, 1),
        lastDate: DateTime(now.year + 10, 12, 31),
        initialDate: _mode == _ViewMode.tabelle
            ? (_selectedDay ?? _focusedDay)
            : _agendaAnchor,
        helpText: 'Zu Datum springen',
        cancelText: 'Abbrechen',
        confirmText: 'Übernehmen',
      );
      if (!mounted) return; // 🔒 wichtig nach await
      if (picked != null) {
        if (_mode == _ViewMode.tabelle) {
          setState(() {
            _focusedDay = picked;
            _selectedDay = picked;
          });
          if (_eventsYear != picked.year) {
            _eventsYear = picked.year;
            _rebuildEventsForYear(_eventsYear);
          }
        } else {
          setState(() => _agendaAnchor = _atMidnight(picked));
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollAgendaTo(_agendaAnchor),
          );
        }
      }
    }
  }

  // ---------- Ausgewählter-Tag-Liste (unter Kalender) ----------
  Widget _buildSelectedDayList() {
    final DateTime day = _selectedDay ?? _focusedDay;
    final List<Mitglied> items = _events[_dayKey(day)] ?? const <Mitglied>[];
    if (items.isEmpty) {
      return const SizedBox(height: 0);
    }

    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(height: 8),
        itemBuilder: (context, index) {
          final m = items[index];
          final String vor = m.vorname;
          final String nach = m.nachname;
          final DateTime dob = m.geburtsDatum;
          final int? age = _ageOnDate(dob, _dayKey(day));

          final String secondary = () {
            final st = m.currentStufe;
            if (st != Stufe.KEINE_STUFE) {
              return st.display;
            }
            final t = _currentTaetigkeitOf(m);
            return t.isNotEmpty ? t : '';
          }();

          String subtitle = '';
          if (age != null && secondary.isNotEmpty) {
            subtitle = '$age - $secondary';
          } else if (age != null) {
            subtitle = '$age';
          } else if (secondary.isNotEmpty) {
            subtitle = secondary;
          }

          return ListTile(
            leading: const Icon(Icons.cake),
            title: Text('$vor $nach'),
            subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
            onTap: () => _openMitgliedDetails(m),
          );
        },
      ),
    );
  }

  /// Filter-Panel mit runden Stufen-Icons wie in der Mitgliederliste
  Widget _buildFilterGroup() {
    return Consumer<MemberListSettingsHandler>(
      builder: (context, settings, _) {
        final Map<String, CustomGroup> gruppen =
            settings.filterOptions.filterGroup;

        final Map<String, CustomGroup> customGruppen = <String, CustomGroup>{};
        for (final entry in gruppen.entries) {
          final String key = entry.key;
          final CustomGroup value = entry.value;
          if (!value.static ||
              (value.stufe != null &&
                  _all.any(
                    (mitglied) => value.stufe == mitglied.currentStufe,
                  ))) {
            customGruppen[key] = value;
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: customGruppen.entries.map((entry) {
                final String groupName = entry.key;
                final CustomGroup group = entry.value;

                final Widget groupImage = (group.stufe == null)
                    ? Icon(group.icon, semanticLabel: '$groupName Filter')
                    : Image.asset(
                        group.stufe!.imagePath ?? Stufe.LEITER.imagePath!,
                        semanticLabel: '$groupName Filter',
                        width: 30.0,
                        height: 30.0,
                        cacheHeight: 100,
                      );

                return GestureDetector(
                  onTap: () {
                    settings.updateFilterGroupActive(groupName, !group.active);
                    _rebuildEventsForYear(_eventsYear);
                    if (_mode == _ViewMode.agenda) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollAgendaTo(_agendaAnchor),
                      );
                    }
                  },
                  child: Container(
                    width: 50.0,
                    height: 50.0,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: group.active
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondaryContainer,
                    ),
                    child: Center(child: groupImage),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

// ────────────── SCHÖNER PILL-TOGGLE ──────────────
class _PillSegmentedControl extends StatelessWidget {
  const _PillSegmentedControl({
    required this.leftLabel,
    required this.rightLabel,
    required this.isRightActive,
    required this.onLeftTap,
    required this.onRightTap,
  });

  final String leftLabel;
  final String rightLabel;
  final bool isRightActive;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: isRightActive
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1.0,
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Die zwei tappbaren Bereiche mit Text
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onLeftTap,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 120),
                            style: TextStyle(
                              fontWeight: isRightActive
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: isRightActive
                                  ? scheme.onSurfaceVariant
                                  : scheme.onPrimaryContainer,
                            ),
                            child: Text(leftLabel),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onRightTap,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 120),
                            style: TextStyle(
                              fontWeight: isRightActive
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isRightActive
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                            child: Text(rightLabel),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────── Agenda-Bausteine ──────────────
class _AgendaSection<T> extends StatelessWidget {
  const _AgendaSection({
    required this.date,
    required this.items,
    required this.itemBuilder,
  });

  final DateTime date;
  final List<T> items;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatDate(date),
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...items.map(itemBuilder),
      ],
    );
  }
}

class _AgendaBirthdayTile extends StatelessWidget {
  const _AgendaBirthdayTile({
    required this.mitglied,
    required this.age,
    this.onTap,
  });

  final Mitglied mitglied;
  final int? age;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.cake,
                  color: _stufeColor(mitglied.currentStufe, context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${mitglied.vorname} ${mitglied.nachname}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final st = mitglied.currentStufe;
                          final String secondary = st != Stufe.KEINE_STUFE
                              ? st.display
                              : '';
                          final String subtitle = () {
                            if (age != null && secondary.isNotEmpty) {
                              return '$age - $secondary';
                            }
                            if (age != null) {
                              return '$age';
                            }
                            if (secondary.isNotEmpty) {
                              return secondary;
                            }
                            return '';
                          }();
                          return subtitle.isNotEmpty
                              ? Text(
                                  subtitle,
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────── Farben nach Stufe (über stufe.farbe) ──────────────
Color _stufeColor(Stufe stufe, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  try {
    final dynamic f =
        stufe.farbe; // erwartet Color, kann aber auch int/String sein
    if (f is Color) return f;
    if (f is int) return Color(f);
    if (f is String) {
      final s = f.trim();
      if (s.startsWith('#')) {
        final hex = s.substring(1);
        final value = int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
        return Color(value);
      }
      if (s.startsWith('0x')) {
        return Color(int.parse(s));
      }
    }
  } catch (_) {}
  // Fallbacks: Leiter → Primary, sonst Secondary
  if (stufe == Stufe.LEITER) {
    return cs.primary;
  } else {
    return cs.secondary;
  }
}

// ────────────── Format-Helper ──────────────
String _formatDate(DateTime d) {
  const wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final wd = wochentage[(d.weekday + 6) % 7];
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$wd, $day.$month.${d.year}';
}
