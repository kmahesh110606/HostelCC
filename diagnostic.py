#!/usr/bin/env python
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'hostel_app.settings')
django.setup()

from students.models import Student
from laundry.models import LaundrySchedule, LaundryRoomRange
from students.utils import resolve_student_for_user

# Get sample data
print("=== Database State ===")
print(f"Total students: {Student.objects.count()}")
print(f"Total laundry schedules: {LaundrySchedule.objects.count()}")
print(f"Active room ranges: {LaundryRoomRange.objects.filter(is_active=True).count()}")
print()

# Get students who don't have schedules
students_without_schedules = []
students_with_schedules = []
students_with_no_block = []

for s in Student.objects.select_related('user', 'block'):
    if not s.block:
        students_with_no_block.append(s.roll_no)
    schedule = LaundrySchedule.objects.filter(student=s).first()
    if schedule:
        students_with_schedules.append(s.roll_no)
    else:
        students_without_schedules.append(s.roll_no)

print(f"Students with schedules: {len(students_with_schedules)}")
print(f"Students WITHOUT schedules: {len(students_without_schedules)}")
print(f"Students with NO block: {len(students_with_no_block)}")
if students_without_schedules:
    print(f"  Sample missing schedules: {students_without_schedules[:10]}")
if students_with_no_block:
    print(f"  No block assigned: {students_with_no_block[:10]}")
print()

# Check active room ranges
print("=== Active Room Ranges (all) ===")
ranges = LaundryRoomRange.objects.filter(is_active=True)
print(f"Total active ranges: {ranges.count()}")
for r in ranges:
    print(f"  Block: {r.block_name}, Rooms: {r.room_from}-{r.room_to}, Day: {r.day_of_week}, Date: {r.scheduled_date}")
