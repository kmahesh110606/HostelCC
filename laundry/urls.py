from rest_framework.routers import DefaultRouter

from .views import LaundryEventViewSet, LaundryHolidayViewSet, LaundryRoomRangeViewSet, LaundryScheduleViewSet

router = DefaultRouter()
router.register("schedules", LaundryScheduleViewSet, basename="laundry-schedules")
router.register("events", LaundryEventViewSet, basename="laundry-events")
router.register("room-ranges", LaundryRoomRangeViewSet, basename="laundry-room-ranges")
router.register("holidays", LaundryHolidayViewSet, basename="laundry-holidays")

urlpatterns = router.urls
