import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

final DateTime ZERO_DATE = DateTime.utc(2026, 1, 24);

const Color kNavy = Color.fromRGBO(0, 42, 92, 1);
const Color kGreen = Color.fromRGBO(122, 193, 66, 1);
const Color kSurfaceMuted = Color(0xFFF4F6F9);
const Color kBorderSubtle = Color(0xFFE3E7EE);

enum TodoStatus {
  notStarted,
  inProgress,
  completed;

  int toCode() => index;

  static TodoStatus fromCode(int code) {
    if (code < 0 || code >= TodoStatus.values.length) {
      return TodoStatus.notStarted;
    }
    return TodoStatus.values[code];
  }

  String get label {
    switch (this) {
      case TodoStatus.notStarted:
        return 'Not started';
      case TodoStatus.inProgress:
        return 'In progress';
      case TodoStatus.completed:
        return 'Completed';
    }
  }

  IconData get icon {
    switch (this) {
      case TodoStatus.notStarted:
        return Icons.radio_button_unchecked;
      case TodoStatus.inProgress:
        return Icons.timelapse;
      case TodoStatus.completed:
        return Icons.check_circle;
    }
  }

  Color get accent {
    switch (this) {
      case TodoStatus.notStarted:
        return const Color(0xFF8A94A6);
      case TodoStatus.inProgress:
        return kNavy;
      case TodoStatus.completed:
        return kGreen;
    }
  }

  Color get tint {
    switch (this) {
      case TodoStatus.notStarted:
        return kSurfaceMuted;
      case TodoStatus.inProgress:
        return const Color.fromRGBO(0, 42, 92, 0.10);
      case TodoStatus.completed:
        return const Color.fromRGBO(122, 193, 66, 0.16);
    }
  }
}

class TodoItem {
  final int id;
  final TodoStatus status;
  final String description;
  final int dateId;

  const TodoItem({
    required this.id,
    required this.status,
    required this.description,
    required this.dateId,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'is_completed': status.toCode(),
      'description': description,
      'day_id': dateId,
    };
  }

  @override
  String toString() {
    return 'TodoItem{id: $id, status: $status, description: $description, dateId: $dateId}';
  }
}

class Day {
  final int id;
  final String date;

  const Day({required this.id, required this.date});

  Map<String, Object?> toMap() {
    return {'id': id, 'date': date};
  }

  @override
  String toString() {
    return 'Day{id: $id, date: $date}';
  }
}

var database;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // .env not present — summarization will surface a clear error at use time.
  }
  database = openDatabase(
    join(await getDatabasesPath(), 'todosdatabase.db'),
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE days(id INTEGER PRIMARY KEY, date TEXT)',
      );
      await db.execute(
        'CREATE TABLE todos(id INTEGER PRIMARY KEY, day_id INTEGER, is_completed INTEGER, description TEXT)',
      );
    },
    version: 1,
  );

  runApp(const DailyTodoApp());
}

Future<void> insertDay(Day day) async {
  final db = await database;
  await db.insert(
    'days',
    day.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> insertTodoItem(TodoItem todoItem) async {
  final db = await database;
  await db.insert(
    'todos',
    todoItem.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> updateTodoItem(TodoItem todoItem) async {
  final db = await database;
  await db.update(
    'todos',
    todoItem.toMap(),
    where: 'id = ?',
    whereArgs: [todoItem.id],
  );
}

Future<List<Day>> days() async {
  final db = await database;
  final List<Map<String, Object?>> dayMaps = await db.query('days');
  return [
    for (final {'id': id as int, 'date': date as String} in dayMaps)
      Day(id: id, date: date),
  ];
}

Future<List<TodoItem>> todoItems() async {
  final db = await database;
  final List<Map<String, Object?>> todoMaps = await db.query('todos');
  return [
    for (final {
      'id': id as int,
      'day_id': dayId as int,
      'is_completed': isCompleted as int,
      'description': description as String
    } in todoMaps)
      TodoItem(
        id: id,
        dateId: dayId,
        status: TodoStatus.fromCode(isCompleted),
        description: description,
      ),
  ];
}

Future<List<TodoItem>> todoItemsForDay(int dayId) async {
  final db = await database;
  final List<Map<String, Object?>> todoMaps = await db.query(
    'todos',
    where: 'day_id = ?',
    whereArgs: [dayId],
  );
  return [
    for (final {
      'id': id as int,
      'day_id': dayId as int,
      'is_completed': isCompleted as int,
      'description': description as String
    } in todoMaps)
      TodoItem(
        id: id,
        dateId: dayId,
        status: TodoStatus.fromCode(isCompleted),
        description: description,
      ),
  ];
}

Future<List<TodoItem>> todoItemsForDayRange(int startDayId, int endDayId) async {
  final db = await database;
  final List<Map<String, Object?>> todoMaps = await db.query(
    'todos',
    where: 'day_id >= ? AND day_id <= ?',
    whereArgs: [startDayId, endDayId],
    orderBy: 'day_id ASC, id ASC',
  );
  return [
    for (final {
      'id': id as int,
      'day_id': dayId as int,
      'is_completed': isCompleted as int,
      'description': description as String
    } in todoMaps)
      TodoItem(
        id: id,
        dateId: dayId,
        status: TodoStatus.fromCode(isCompleted),
        description: description,
      ),
  ];
}

Future<void> deleteTodoItem(int todoId) async {
  final db = await database;
  await db.delete(
    'todos',
    where: 'id = ?',
    whereArgs: [todoId],
  );
}

class DailyTodoApp extends StatelessWidget {
  const DailyTodoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Todo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNavy,
          primary: kNavy,
          secondary: kGreen,
          background: Colors.white,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Jost',
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavy,
          foregroundColor: Colors.white,
        ),
        splashFactory: InkSparkle.splashFactory,
        useMaterial3: true,
      ),
      home: const DailyTodoPage(),
    );
  }
}

class DailyTodoPage extends StatefulWidget {
  const DailyTodoPage({Key? key}) : super(key: key);

  @override
  State<DailyTodoPage> createState() => _DailyTodoPageState();
}

class _DailyTodoPageState extends State<DailyTodoPage> {
  DateTime currentDate = DateTime.now();
  final Map<String, List<Todo>> todosByDate = {};
  final Map<String, List<int>> todoIdsByDate = {}; // Track todo IDs for deletion
  final TextEditingController todoController = TextEditingController();
  final Map<int, int> _todoCountersByDay = {};

  @override
  void initState() {
    super.initState();
    // Ensure current date is set to today's date (normalized to midnight)
    final now = DateTime.now();
    currentDate = DateTime(now.year, now.month, now.day);
    loadTodosForCurrentDate();
  }

  Future<void> loadTodosForCurrentDate() async {
    int dayId = getDayId(currentDate);
    String dateKey = getDateKey(currentDate);
    
    print('Loading todos for date: $dateKey, dayId: $dayId');
    
    List<TodoItem> dbTodos = await todoItemsForDay(dayId);
    
    setState(() {
      final key = getDateKey(currentDate);
      todosByDate[key] = dbTodos.map((todoItem) =>
        Todo(text: todoItem.description, status: todoItem.status)
      ).toList();
      
      todoIdsByDate[key] = dbTodos.map((todoItem) => todoItem.id).toList();
      
      // Update counter to avoid ID collisions
      if (dbTodos.isNotEmpty) {
        int maxLocalId = dbTodos.map((t) => t.id % 10000).reduce((a, b) => a > b ? a : b);
        _todoCountersByDay[dayId] = maxLocalId + 1;
      }
    });
    
    print('Loaded ${dbTodos.length} todos for day $dayId (date: $dateKey)');
  }

  String getDateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  String getFormattedDate(DateTime date) =>
      DateFormat('EEEE, MMMM d, yyyy').format(date);

  int getDayId(DateTime date) {
    // Normalize to just the date part (ignore time)
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedZero = DateTime(ZERO_DATE.year, ZERO_DATE.month, ZERO_DATE.day);
    return normalizedDate.difference(normalizedZero).inDays;
  }

  List<Todo> getTodosForCurrentDate() =>
      todosByDate[getDateKey(currentDate)] ?? [];

  void addTodo() {
    final text = todoController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      final key = getDateKey(currentDate);
      todosByDate.putIfAbsent(key, () => []);
      todosByDate[key]!.add(Todo(text: text));
      
      // Initialize ID list for this date if needed
      todoIdsByDate.putIfAbsent(key, () => []);
      // Temporarily add -1, will be assigned real ID when pushed to DB
      todoIdsByDate[key]!.add(-1);
      
      todoController.clear();
    });
  }

  void setTodoStatus(int index, TodoStatus newStatus) async {
    setState(() {
      final key = getDateKey(currentDate);
      todosByDate[key]![index].status = newStatus;
    });

    final key = getDateKey(currentDate);
    if (todoIdsByDate.containsKey(key) &&
        index < todoIdsByDate[key]!.length &&
        todoIdsByDate[key]![index] != -1) {
      int todoId = todoIdsByDate[key]![index];
      int dayId = getDayId(currentDate);
      final todo = todosByDate[key]![index];

      TodoItem todoItem = TodoItem(
        id: todoId,
        dateId: dayId,
        status: todo.status,
        description: todo.text,
      );

      await updateTodoItem(todoItem);
      print('Updated todo $todoId status: ${todo.status}');
    }
  }

  void deleteTodo(int index) async {
    final key = getDateKey(currentDate);
    
    // Get the todo ID if it exists
    if (todoIdsByDate.containsKey(key) && 
        index < todoIdsByDate[key]!.length &&
        todoIdsByDate[key]![index] != -1) {
      int todoId = todoIdsByDate[key]![index];
      await deleteTodoItem(todoId);
      print('Deleted todo with ID: $todoId');
    }
    
    setState(() {
      todosByDate[key]!.removeAt(index);
      if (todoIdsByDate.containsKey(key) && index < todoIdsByDate[key]!.length) {
        todoIdsByDate[key]!.removeAt(index);
      }
    });
  }

  Future<void> pushDayAndTodos() async {
    int dayId = getDayId(currentDate);
    Day toPush = Day(id: dayId, date: getDateKey(currentDate));

    await insertDay(toPush);

    // Push all todos for current day
    final key = getDateKey(currentDate);
    final todos = todosByDate[key] ?? [];
    
    // Initialize counter for this day if not exists
    if (!_todoCountersByDay.containsKey(dayId)) {
      _todoCountersByDay[dayId] = 0;
    }
    
    // Initialize ID list for this date if needed
    todoIdsByDate.putIfAbsent(key, () => []);
    
    for (int i = 0; i < todos.length; i++) {
      final todo = todos[i];
      
      // Skip if this todo already has a valid ID (already in database)
      if (i < todoIdsByDate[key]!.length && todoIdsByDate[key]![i] != -1) {
        continue;
      }
      
      // Create unique ID: dayId * 10000 + counter
      // This allows up to 10,000 todos per day without collisions
      int todoId = (dayId * 10000) + _todoCountersByDay[dayId]!;
      _todoCountersByDay[dayId] = _todoCountersByDay[dayId]! + 1;
      
      // Store the ID so we can delete it later
      if (i < todoIdsByDate[key]!.length) {
        todoIdsByDate[key]![i] = todoId;
      } else {
        todoIdsByDate[key]!.add(todoId);
      }
      
      TodoItem todoItem = TodoItem(
        id: todoId,
        dateId: dayId,
        status: todo.status,
        description: todo.text,
      );
      await insertTodoItem(todoItem);
    }

    // Print database contents for debugging
    print('Days: ${await days()}');
    print('Todos: ${await todoItems()}');
  }

  void goToPreviousDay() async {
    await pushDayAndTodos();
    setState(() {
      currentDate = currentDate.subtract(const Duration(days: 1));
    });
    await loadTodosForCurrentDate();
  }

  void goToNextDay() async {
    await pushDayAndTodos();
    setState(() {
      currentDate = currentDate.add(const Duration(days: 1));
    });
    await loadTodosForCurrentDate();
  }

  void goToToday() async {
    await pushDayAndTodos();
    setState(() {
      currentDate = DateTime.now();
    });
    await loadTodosForCurrentDate();
  }

  Future<void> openSummarizeDialog() async {
    await pushDayAndTodos();

    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kSurfaceMuted,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: kNavy, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Summarize my todos',
                      style: TextStyle(
                        fontFamily: 'Bungee',
                        fontSize: 16,
                        color: kNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Pick a window and I\'ll send your todos to an LLM and summarize what you accomplished.',
                style: TextStyle(
                  fontFamily: 'Jost',
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _SummaryRangeOption(
                title: 'Past week',
                subtitle: 'Last 7 days',
                onTap: () => Navigator.of(ctx).pop(7),
              ),
              const SizedBox(height: 10),
              _SummaryRangeOption(
                title: 'Past month',
                subtitle: 'Last 30 days',
                onTap: () => Navigator.of(ctx).pop(30),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: 'Jost',
                      color: kNavy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;
    await runSummary(choice);
  }

  Future<void> runSummary(int days) async {
    final today = DateTime.now();
    final endDayId = getDayId(today);
    final startDayId = endDayId - (days - 1);

    final items = await todoItemsForDayRange(startDayId, endDayId);

    if (!mounted) return;
    if (items.isEmpty) {
      _showResultDialog(
        title: 'Nothing to summarize',
        body:
            'You don\'t have any todos in the past $days days. Add some todos and try again.',
      );
      return;
    }

    final prompt = _buildSummaryPrompt(items, days, startDayId);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingDialog(),
    );

    String summary;
    try {
      summary = await _callOpenAI(prompt);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showResultDialog(
        title: 'Couldn\'t summarize',
        body: e.toString(),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showResultDialog(
      title: 'Summary — past $days days',
      body: summary,
    );
  }

  String _buildSummaryPrompt(
      List<TodoItem> items, int days, int startDayId) {
    final byDay = <int, List<TodoItem>>{};
    for (final item in items) {
      byDay.putIfAbsent(item.dateId, () => []).add(item);
    }
    final sortedDayIds = byDay.keys.toList()..sort();

    final buffer = StringBuffer();
    buffer.writeln('Here are my todos from the past $days days, grouped by day.');
    buffer.writeln('Each item is marked with its status: '
        '[done] = completed, [wip] = in progress, [todo] = not started.');
    buffer.writeln();

    for (final dayId in sortedDayIds) {
      final dayDate = ZERO_DATE.add(Duration(days: dayId));
      final label = DateFormat('EEEE, MMM d').format(dayDate);
      buffer.writeln('## $label');
      for (final t in byDay[dayId]!) {
        final tag = switch (t.status) {
          TodoStatus.completed => 'done',
          TodoStatus.inProgress => 'wip',
          TodoStatus.notStarted => 'todo',
        };
        buffer.writeln('- [$tag] ${t.description}');
      }
      buffer.writeln();
    }

    buffer.writeln(
        'Please summarize what I accomplished in this period. Highlight: '
        '(1) the main themes of what got done, (2) what is still in progress, '
        '(3) anything that has been outstanding for a while, '
        '(4) a one-line encouraging takeaway. Use short paragraphs and bullets where helpful. Keep it under ~250 words.');

    return buffer.toString();
  }

  Future<String> _callOpenAI(String userPrompt) async {
    final key = dotenv.maybeGet('OPEN_AI_KEY') ?? dotenv.maybeGet('OPENAI_API_KEY');
    if (key == null || key.isEmpty) {
      throw 'No OpenAI API key found. Add OPEN_AI_KEY to your .env file.';
    }

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a friendly productivity coach summarizing a user\'s personal todo list. Be concrete, warm, and specific.',
          },
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.5,
      }),
    );

    if (response.statusCode != 200) {
      throw 'OpenAI returned ${response.statusCode}: ${response.body}';
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final content = json['choices']?[0]?['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw 'OpenAI returned an empty response.';
    }
    return content.trim();
  }

  void _showResultDialog({required String title, required String body}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: kGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Bungee',
                          fontSize: 15,
                          color: kNavy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      body,
                      style: const TextStyle(
                        fontFamily: 'Jost',
                        fontSize: 14.5,
                        color: kNavy,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: body));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16, color: kNavy),
                      label: const Text(
                        'Copy',
                        style: TextStyle(
                          fontFamily: 'Jost',
                          color: kNavy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontFamily: 'Jost',
                          color: kNavy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todos = getTodosForCurrentDate();
    final isToday = getDateKey(currentDate) == getDateKey(DateTime.now());
    final completedCount =
        todos.where((t) => t.status == TodoStatus.completed).length;
    final progress = todos.isEmpty ? 0.0 : completedCount / todos.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(isToday, todos.length, completedCount, progress),
            _buildAddTodoBar(),
            Expanded(
              child: todos.isEmpty
                  ? _buildEmptyState()
                  : _buildTodoList(todos),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      bool isToday, int total, int completed, double progress) {
    final dayLabel = isToday
        ? 'Today'
        : DateFormat('EEEE').format(currentDate);
    final dateLine = DateFormat('MMMM d, yyyy').format(currentDate);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: kBorderSubtle, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoundIconButton(
                icon: Icons.chevron_left,
                onTap: goToPreviousDay,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      dayLabel,
                      style: const TextStyle(
                        fontFamily: 'Bungee',
                        fontSize: 22,
                        color: kNavy,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLine,
                      style: TextStyle(
                        fontFamily: 'Jost',
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: Icons.auto_awesome,
                onTap: openSummarizeDialog,
              ),
              const SizedBox(width: 8),
              if (!isToday)
                _PillButton(
                  label: 'Today',
                  onTap: goToToday,
                )
              else
                _RoundIconButton(
                  icon: Icons.chevron_right,
                  onTap: goToNextDay,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: kSurfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(kGreen),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                total == 0 ? '—' : '$completed / $total',
                style: const TextStyle(
                  fontFamily: 'Jost',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kNavy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddTodoBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: kSurfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorderSubtle),
              ),
              child: TextField(
                controller: todoController,
                decoration: const InputDecoration(
                  hintText: 'Add a new todo…',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  hintStyle: TextStyle(
                    fontFamily: 'Jost',
                    fontSize: 16,
                    color: Color(0xFF8A94A6),
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'Jost',
                  fontSize: 16,
                  color: kNavy,
                ),
                onSubmitted: (_) => addTodo(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: kGreen,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: addTodo,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                child: const Icon(Icons.add, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: kSurfaceMuted,
              borderRadius: BorderRadius.circular(38),
            ),
            child: const Icon(
              Icons.checklist_rounded,
              size: 36,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nothing here yet',
            style: TextStyle(
              fontFamily: 'Bungee',
              fontSize: 18,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add a todo above to get started.',
            style: TextStyle(
              fontFamily: 'Jost',
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoList(List<Todo> todos) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: todos.length,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final key = getDateKey(currentDate);
          final todo = todosByDate[key]!.removeAt(oldIndex);
          todosByDate[key]!.insert(newIndex, todo);

          if (todoIdsByDate.containsKey(key)) {
            final todoId = todoIdsByDate[key]!.removeAt(oldIndex);
            todoIdsByDate[key]!.insert(newIndex, todoId);
          }
        });
      },
      itemBuilder: (context, index) {
        final todo = todos[index];
        return _TodoCard(
          key: ValueKey('todo-$index-${todo.text}'),
          index: index,
          todo: todo,
          onStatusChange: (status) => setTodoStatus(index, status),
          onDelete: () => deleteTodo(index),
        );
      },
    );
  }

  @override
  void dispose() {
    todoController.dispose();
    super.dispose();
  }
}

class Todo {
  String text;
  TodoStatus status;

  Todo({
    required this.text,
    this.status = TodoStatus.notStarted,
  });
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurfaceMuted,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: kNavy),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kNavy,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Jost',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRangeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SummaryRangeOption({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Jost',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Jost',
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: kNavy, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(kGreen),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Summarizing…',
              style: const TextStyle(
                fontFamily: 'Jost',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: kNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  final int index;
  final Todo todo;
  final ValueChanged<TodoStatus> onStatusChange;
  final VoidCallback onDelete;

  const _TodoCard({
    super.key,
    required this.index,
    required this.todo,
    required this.onStatusChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = todo.status == TodoStatus.completed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorderSubtle),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0A1F3D),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            _StatusChip(
              status: todo.status,
              onChanged: onStatusChange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                todo.text,
                style: TextStyle(
                  fontFamily: 'Jost',
                  fontSize: 16,
                  height: 1.3,
                  decoration:
                      isCompleted ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.grey.shade500,
                  decorationThickness: 2,
                  color: isCompleted ? Colors.grey.shade500 : kNavy,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded,
                  color: Colors.grey.shade500, size: 20),
              tooltip: 'Delete',
              splashRadius: 20,
              onPressed: onDelete,
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.drag_indicator,
                  color: Colors.grey.shade400,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final TodoStatus status;
  final ValueChanged<TodoStatus> onChanged;

  const _StatusChip({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TodoStatus>(
      tooltip: 'Change status',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => TodoStatus.values
          .map(
            (s) => PopupMenuItem<TodoStatus>(
              value: s,
              child: Row(
                children: [
                  Icon(s.icon, color: s.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    s.label,
                    style: TextStyle(
                      fontFamily: 'Jost',
                      fontSize: 14,
                      fontWeight: s == status ? FontWeight.w600 : FontWeight.w400,
                      color: kNavy,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: status.tint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, color: status.accent, size: 16),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: TextStyle(
                fontFamily: 'Jost',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: status.accent,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, color: status.accent, size: 16),
          ],
        ),
      ),
    );
  }
}