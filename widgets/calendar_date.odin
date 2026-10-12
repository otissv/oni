package oni_widgets

import dt "core:time/datetime"
import "core:time"
import "core:fmt"
import "core:slice"
import "core:strconv"

/*
Civil calendar date (year/month/day). Zero value means unset.
*/
Calendar_Date :: struct {
	year:  i64,
	month: i8,
	day:   i8,
}

/*
Inclusive date range used by range selection and matchers.
*/
Calendar_Range :: struct {
	from:     Calendar_Date,
	to:       Calendar_Date,
	has_from: bool,
	has_to:   bool,
}

/*
Selection mode for `Calendar`, matching React DayPicker modes.
*/
Calendar_Mode :: enum {
	NONE,
	SINGLE,
	MULTIPLE,
	RANGE,
}

/*
Weekday used for `week_starts_on` and formatters. Sunday is zero.
*/
Calendar_Weekday :: enum i8 {
	SUNDAY = 0,
	MONDAY,
	TUESDAY,
	WEDNESDAY,
	THURSDAY,
	FRIDAY,
	SATURDAY,
}

/*
Snapshot of the active selection passed to `on_select`.

`multiple` is valid only for the duration of the callback and uses
`context.temp_allocator` — copy it if it must outlive the call.
*/
Calendar_Selection :: struct {
	mode:       Calendar_Mode,
	single:     Calendar_Date,
	has_single: bool,
	multiple:   []Calendar_Date,
	range:      Calendar_Range,
}

CALENDAR_MAX_MONTHS :: 12
CALENDAR_MAX_MULTIPLE :: 512
CALENDAR_GRID_DAYS :: 42
CALENDAR_WEEK_DAYS :: 7
CALENDAR_WEEK_ROWS :: 6

@(private)
CALENDAR_MONTH_NAMES := [12]string {
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
}

@(private)
CALENDAR_WEEKDAY_SHORT := [7]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}

@(private)
CALENDAR_MONTH_SHORT := [12]string {
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec",
}

/*
Returns whether `date` has a non-zero year/month/day and is a valid Gregorian date.
*/
Calendar_Date_Valid :: proc(date: Calendar_Date) -> bool {
	if date.year == 0 && date.month == 0 && date.day == 0 {
		return false
	}

	_, err := dt.components_to_date(date.year, date.month, date.day)

	return err == .None
}

/*
Returns whether two dates refer to the same civil day.
*/
Calendar_Date_Equal :: proc(a, b: Calendar_Date) -> bool {
	return a.year == b.year && a.month == b.month && a.day == b.day
}

/*
Orders dates chronologically. Invalid dates sort after valid ones.
*/
Calendar_Date_Compare :: proc(a, b: Calendar_Date) -> int {
	a_ok := Calendar_Date_Valid(a)
	b_ok := Calendar_Date_Valid(b)

	if !a_ok && !b_ok {
		return 0
	}

	if !a_ok {
		return 1
	}

	if !b_ok {
		return -1
	}

	if a.year != b.year {
		return a.year < b.year ? -1 : 1
	}

	if a.month != b.month {
		return a.month < b.month ? -1 : 1
	}

	if a.day != b.day {
		return a.day < b.day ? -1 : 1
	}

	return 0
}

/*
Returns true when `date` is strictly before `other`.
*/
Calendar_Date_Before :: proc(date, other: Calendar_Date) -> bool {
	return Calendar_Date_Compare(date, other) < 0
}

/*
Returns true when `date` is strictly after `other`.
*/
Calendar_Date_After :: proc(date, other: Calendar_Date) -> bool {
	return Calendar_Date_Compare(date, other) > 0
}

/*
Normalizes a range so `from <= to` when both ends are set.
*/
Calendar_Range_Normalize :: proc(range: Calendar_Range) -> Calendar_Range {
	out := range

	if out.has_from && out.has_to && Calendar_Date_After(out.from, out.to) {
		out.from, out.to = out.to, out.from
	}

	return out
}

/*
Returns whether `date` lies inside an inclusive range.
*/
Calendar_Range_Contains :: proc(range: Calendar_Range, date: Calendar_Date) -> bool {
	if !Calendar_Date_Valid(date) {
		return false
	}

	norm := Calendar_Range_Normalize(range)

	if norm.has_from && norm.has_to {
		return !Calendar_Date_Before(date, norm.from) && !Calendar_Date_After(date, norm.to)
	}

	if norm.has_from {
		return Calendar_Date_Equal(date, norm.from)
	}

	return false
}

/*
Converts a calendar date to a datetime ordinal day number.
*/
Calendar_Date_Ordinal :: proc(date: Calendar_Date) -> (ordinal: dt.Ordinal, ok: bool) {
	ord, err := dt.components_to_ordinal(date.year, date.month, date.day)

	if err != .None {
		return 0, false
	}

	return ord, true
}

/*
Builds a calendar date from an ordinal.
*/
Calendar_Date_From_Ordinal :: proc(ordinal: dt.Ordinal) -> (date: Calendar_Date, ok: bool) {
	d, err := dt.ordinal_to_date(ordinal)

	if err != .None {
		return {}, false
	}

	return Calendar_Date{year = d.year, month = d.month, day = d.day}, true
}

/*
Adds `days` to a date. Returns the zero date when the result is invalid.
*/
Calendar_Date_Add_Days :: proc(date: Calendar_Date, days: i64) -> Calendar_Date {
	ord, ok := Calendar_Date_Ordinal(date)

	if !ok {
		return {}
	}

	out, out_ok := Calendar_Date_From_Ordinal(ord + dt.Ordinal(days))

	if !out_ok {
		return {}
	}

	return out
}

/*
Returns the number of whole days from `from` to `to` (can be negative).
*/
Calendar_Date_Diff_Days :: proc(from, to: Calendar_Date) -> (days: i64, ok: bool) {
	a, a_ok := Calendar_Date_Ordinal(from)
	b, b_ok := Calendar_Date_Ordinal(to)

	if !a_ok || !b_ok {
		return 0, false
	}

	return i64(b - a), true
}

/*
Returns the weekday for a valid date.
*/
Calendar_Date_Weekday :: proc(date: Calendar_Date) -> (weekday: Calendar_Weekday, ok: bool) {
	ord, ord_ok := Calendar_Date_Ordinal(date)

	if !ord_ok {
		return .SUNDAY, false
	}

	return Calendar_Weekday(dt.day_of_week(ord)), true
}

@(private)
calendar_month_days := [13]i8{0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

/*
Returns days in the given month (1-12), accounting for leap years.
*/
Calendar_Days_In_Month :: proc(year: i64, month: i8) -> int {
	if month < 1 || month > 12 {
		return 0
	}

	days := int(calendar_month_days[month])

	if month == 2 && dt.is_leap_year(year) {
		days = 29
	}

	return days
}

/*
Clamps day into the valid range for year/month.
*/
Calendar_Date_Clamp_Day :: proc(year: i64, month: i8, day: i8) -> Calendar_Date {
	if month < 1 || month > 12 {
		return {}
	}

	max_day := i8(Calendar_Days_In_Month(year, month))

	if max_day <= 0 {
		return {}
	}

	d := day

	if d < 1 {
		d = 1
	}

	if d > max_day {
		d = max_day
	}

	return {year = year, month = month, day = d}
}

/*
Returns the first day of the month containing `date`.
*/
Calendar_Start_Of_Month :: proc(date: Calendar_Date) -> Calendar_Date {
	if date.year == 0 && date.month == 0 {
		return {}
	}

	month := date.month

	if month < 1 || month > 12 {
		return {}
	}

	return {year = date.year, month = month, day = 1}
}

/*
Adds months to a year/month pair, clamping day when needed.
*/
Calendar_Date_Add_Months :: proc(date: Calendar_Date, months: int) -> Calendar_Date {
	if date.year == 0 && date.month == 0 {
		return {}
	}

	month := int(date.month)

	if month < 1 || month > 12 {
		return {}
	}

	total := int(date.year) * 12 + (month - 1) + months
	year := total / 12
	mod := total % 12

	if mod < 0 {
		mod += 12
		year -= 1
	}

	day := date.day

	if day < 1 {
		day = 1
	}

	return Calendar_Date_Clamp_Day(i64(year), i8(mod + 1), day)
}

/*
Returns today's civil date from the system clock.
*/
Calendar_Today :: proc() -> Calendar_Date {
	now := time.now()
	year, month, day := time.date(now)

	return {year = i64(year), month = i8(month), day = i8(day)}
}

/*
ISO-like week number (1-53) for the week containing `date`, Monday-based.
*/
Calendar_Week_Number :: proc(date: Calendar_Date) -> (week: int, ok: bool) {
	ord, ord_ok := Calendar_Date_Ordinal(date)

	if !ord_ok {
		return 0, false
	}

	// ISO week date: week containing the year's first Thursday.
	weekday := int(dt.day_of_week(ord)) // Sunday=0 … Saturday=6
	// Convert to Monday=0 … Sunday=6
	iso_weekday := (weekday + 6) % 7
	thursday := ord + dt.Ordinal(3 - iso_weekday)
	thu_date, thu_ok := Calendar_Date_From_Ordinal(thursday)

	if !thu_ok {
		return 0, false
	}

	year_start, start_ok := Calendar_Date_Ordinal({year = thu_date.year, month = 1, day = 1})

	if !start_ok {
		return 0, false
	}

	return int((thursday - year_start) / 7) + 1, true
}

/*
Formats `YYYY-MM-DD` into `allocator` (defaults to temp).
*/
Calendar_Format_ISO :: proc(date: Calendar_Date, allocator := context.temp_allocator) -> string {
	if !Calendar_Date_Valid(date) {
		return ""
	}

	return fmt.aprintf("%04d-%02d-%02d", date.year, int(date.month), int(date.day), allocator = allocator)
}

/*
Default English caption: `Month YYYY`.
*/
Calendar_Format_Month :: proc(date: Calendar_Date, allocator := context.temp_allocator) -> string {
	month := date.month

	if month < 1 || month > 12 {
		return ""
	}

	return fmt.aprintf("%s %d", CALENDAR_MONTH_NAMES[month - 1], date.year, allocator = allocator)
}

/*
Default short weekday label (`Su` … `Sa`).
*/
Calendar_Format_Weekday :: proc(
	weekday: Calendar_Weekday,
	allocator := context.temp_allocator,
) -> string {
	idx := int(weekday)

	if idx < 0 || idx > 6 {
		return ""
	}

	return CALENDAR_WEEKDAY_SHORT[idx]
}

/*
Default day-of-month label.
*/
Calendar_Format_Day :: proc(date: Calendar_Date, allocator := context.temp_allocator) -> string {
	if !Calendar_Date_Valid(date) {
		return ""
	}

	return fmt.aprintf("%d", int(date.day), allocator = allocator)
}

/*
Long English date: `Month D, YYYY` (e.g. `January 20, 2026`).
*/
Calendar_Format_Long :: proc(date: Calendar_Date, allocator := context.temp_allocator) -> string {
	if !Calendar_Date_Valid(date) {
		return ""
	}

	return fmt.aprintf(
		"%s %d, %d",
		CALENDAR_MONTH_NAMES[date.month - 1],
		int(date.day),
		date.year,
		allocator = allocator,
	)
}

/*
Medium English date: `Mon D, YYYY` (e.g. `Jan 20, 2026`).
*/
Calendar_Format_Medium :: proc(date: Calendar_Date, allocator := context.temp_allocator) -> string {
	if !Calendar_Date_Valid(date) {
		return ""
	}

	return fmt.aprintf(
		"%s %d, %d",
		CALENDAR_MONTH_SHORT[date.month - 1],
		int(date.day),
		date.year,
		allocator = allocator,
	)
}

/*
Parses a strict `YYYY-MM-DD` civil date. Returns ok=false when invalid.
*/
Calendar_Parse_ISO :: proc(s: string) -> (date: Calendar_Date, ok: bool) {
	if len(s) != 10 {
		return {}, false
	}

	if s[4] != '-' || s[7] != '-' {
		return {}, false
	}

	year, y_ok := strconv.parse_i64(s[0:4])

	if !y_ok {
		return {}, false
	}

	month, m_ok := strconv.parse_int(s[5:7])

	if !m_ok {
		return {}, false
	}

	day, d_ok := strconv.parse_int(s[8:10])

	if !d_ok {
		return {}, false
	}

	date = {
		year  = year,
		month = i8(month),
		day   = i8(day),
	}

	if !Calendar_Date_Valid(date) {
		return {}, false
	}

	return date, true
}

/*
One cell in a month grid, including outside-month padding days.
*/
Calendar_Day_Cell :: struct {
	date:      Calendar_Date,
	outside:   bool,
	hidden:    bool,
	disabled:  bool,
	today:     bool,
	selected:  bool,
	range_start: bool,
	range_end:   bool,
	range_middle: bool,
	focused:   bool,
}

/*
Builds the 6×7 day grid for `month` (day field ignored; uses year/month).
*/
Calendar_Build_Month_Grid :: proc(
	month: Calendar_Date,
	week_starts_on: Calendar_Weekday,
	today: Calendar_Date,
	show_outside_days: bool,
	hidden: proc(date: Calendar_Date) -> bool,
	disabled: proc(date: Calendar_Date) -> bool,
	is_selected: proc(date: Calendar_Date) -> bool,
	range: Calendar_Range,
	focused: Calendar_Date,
) -> (
	cells: [CALENDAR_GRID_DAYS]Calendar_Day_Cell,
	ok: bool,
) {
	start := Calendar_Start_Of_Month(month)

	if start.year == 0 {
		return {}, false
	}

	first_weekday, weekday_ok := Calendar_Date_Weekday(start)

	if !weekday_ok {
		return {}, false
	}

	offset := (int(first_weekday) - int(week_starts_on) + CALENDAR_WEEK_DAYS) % CALENDAR_WEEK_DAYS
	grid_start := Calendar_Date_Add_Days(start, -i64(offset))
	norm_range := Calendar_Range_Normalize(range)

	for i in 0 ..< CALENDAR_GRID_DAYS {
		date := Calendar_Date_Add_Days(grid_start, i64(i))
		outside := date.month != start.month || date.year != start.year
		cell := Calendar_Day_Cell {
			date    = date,
			outside = outside,
			today   = Calendar_Date_Valid(today) && Calendar_Date_Equal(date, today),
			focused = Calendar_Date_Valid(focused) && Calendar_Date_Equal(date, focused),
		}

		if outside && !show_outside_days {
			cell.hidden = true
			cells[i] = cell
			continue
		}

		if hidden != nil && hidden(date) {
			cell.hidden = true
		}

		if disabled != nil && disabled(date) {
			cell.disabled = true
		}

		if is_selected != nil && is_selected(date) {
			cell.selected = true
		}

		if norm_range.has_from && Calendar_Date_Equal(date, norm_range.from) {
			cell.range_start = true
			cell.selected = true
		}

		if norm_range.has_to && Calendar_Date_Equal(date, norm_range.to) {
			cell.range_end = true
			cell.selected = true
		}

		if norm_range.has_from &&
		   norm_range.has_to &&
		   Calendar_Range_Contains(norm_range, date) &&
		   !cell.range_start &&
		   !cell.range_end {
			cell.range_middle = true
			cell.selected = true
		}

		cells[i] = cell
	}

	return cells, true
}

/*
Returns whether `date` appears in `dates`.
*/
Calendar_Dates_Contains :: proc(dates: []Calendar_Date, date: Calendar_Date) -> bool {
	for d in dates {
		if Calendar_Date_Equal(d, date) {
			return true
		}
	}

	return false
}

/*
Copies `dates` into a new slice allocated with `allocator` (default: temp).

Pass `context.allocator` when the slice must outlive the current frame.
*/
Calendar_Dates_Clone :: proc(
	dates: []Calendar_Date,
	allocator := context.temp_allocator,
) -> []Calendar_Date {
	if len(dates) == 0 {
		return nil
	}

	out := make([]Calendar_Date, len(dates), allocator)
	copy(out, dates)

	return out
}

/*
Toggles `date` inside a multiple-selection list subject to min/max.

Returns the next list on `allocator`. Does not free `current`.
*/
Calendar_Toggle_Multiple :: proc(
	current: []Calendar_Date,
	date: Calendar_Date,
	min_count: int,
	max_count: int,
	allocator := context.temp_allocator,
) -> (
	next: []Calendar_Date,
	changed: bool,
) {
	if !Calendar_Date_Valid(date) {
		return Calendar_Dates_Clone(current, allocator), false
	}

	if Calendar_Dates_Contains(current, date) {
		if min_count > 0 && len(current) <= min_count {
			return Calendar_Dates_Clone(current, allocator), false
		}

		out := make([dynamic]Calendar_Date, 0, len(current), allocator)

		for d in current {
			if !Calendar_Date_Equal(d, date) {
				append(&out, d)
			}
		}

		return out[:], true
	}

	if max_count > 0 && len(current) >= max_count {
		return Calendar_Dates_Clone(current, allocator), false
	}

	if len(current) >= CALENDAR_MAX_MULTIPLE {
		return Calendar_Dates_Clone(current, allocator), false
	}

	out := make([]Calendar_Date, len(current) + 1, allocator)
	copy(out, current)
	out[len(current)] = date
	slice.sort_by(out, proc(a, b: Calendar_Date) -> bool {
		return Calendar_Date_Compare(a, b) < 0
	})

	return out, true
}

/*
Applies a day click to a range selection (DayPicker semantics).
*/
Calendar_Apply_Range_Click :: proc(
	current: Calendar_Range,
	date: Calendar_Date,
	min_days: int,
	max_days: int,
) -> (
	next: Calendar_Range,
	changed: bool,
) {
	if !Calendar_Date_Valid(date) {
		return current, false
	}

	// Fresh start when complete or empty.
	if !current.has_from || (current.has_from && current.has_to) {
		return {from = date, has_from = true}, true
	}

	from := current.from
	to := date

	if Calendar_Date_Before(to, from) {
		from, to = to, from
	}

	diff, ok := Calendar_Date_Diff_Days(from, to)

	if !ok {
		return current, false
	}

	length := int(diff) + 1

	if min_days > 0 && length < min_days {
		return current, false
	}

	if max_days > 0 && length > max_days {
		return current, false
	}

	return {from = from, to = to, has_from = true, has_to = true}, true
}

/*
Applies a single-mode click. When `required`, the selection cannot clear.
*/
Calendar_Apply_Single_Click :: proc(
	current: Calendar_Date,
	has_current: bool,
	date: Calendar_Date,
	required: bool,
) -> (
	next: Calendar_Date,
	has_next: bool,
	changed: bool,
) {
	if !Calendar_Date_Valid(date) {
		return current, has_current, false
	}

	if has_current && Calendar_Date_Equal(current, date) {
		if required {
			return current, true, false
		}

		return {}, false, true
	}

	return date, true, true
}

/*
Clamps a displayed month into optional start/end month bounds.
*/
Calendar_Clamp_Month :: proc(
	month: Calendar_Date,
	start_month: Calendar_Date,
	end_month: Calendar_Date,
) -> Calendar_Date {
	m := Calendar_Start_Of_Month(month)

	if m.year == 0 {
		return m
	}

	if start_month.year != 0 || start_month.month != 0 {
		start := Calendar_Start_Of_Month(start_month)

		if start.year != 0 && Calendar_Date_Before(m, start) {
			m = start
		}
	}

	if end_month.year != 0 || end_month.month != 0 {
		end := Calendar_Start_Of_Month(end_month)

		if end.year != 0 && Calendar_Date_After(m, end) {
			m = end
		}
	}

	return m
}

/*
Returns whether navigating from `month` by `delta_months` is allowed.
*/
Calendar_Can_Navigate :: proc(
	month: Calendar_Date,
	delta_months: int,
	start_month: Calendar_Date,
	end_month: Calendar_Date,
) -> bool {
	next := Calendar_Date_Add_Months(Calendar_Start_Of_Month(month), delta_months)
	clamped := Calendar_Clamp_Month(next, start_month, end_month)

	return Calendar_Date_Equal(Calendar_Start_Of_Month(next), clamped)
}

/*
Matcher: date is before `bound` (exclusive).
*/
Calendar_Match_Before :: proc(date, bound: Calendar_Date) -> bool {
	return Calendar_Date_Valid(bound) && Calendar_Date_Before(date, bound)
}

/*
Matcher: date is after `bound` (exclusive).
*/
Calendar_Match_After :: proc(date, bound: Calendar_Date) -> bool {
	return Calendar_Date_Valid(bound) && Calendar_Date_After(date, bound)
}

/*
Matcher: date falls on Saturday or Sunday.
*/
Calendar_Match_Weekend :: proc(date: Calendar_Date) -> bool {
	weekday, ok := Calendar_Date_Weekday(date)

	return ok && (weekday == .SATURDAY || weekday == .SUNDAY)
}

/*
Matcher: date equals `target`.
*/
Calendar_Match_Date :: proc(date, target: Calendar_Date) -> bool {
	return Calendar_Date_Valid(target) && Calendar_Date_Equal(date, target)
}
