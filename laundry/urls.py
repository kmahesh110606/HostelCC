from rest_framework.routers import DefaultRouter

from .views import LaundryEventViewSet, LaundryRoomRangeViewSet, LaundryScheduleViewSet

router = DefaultRouter()
router.register("schedules", LaundryScheduleViewSet, basename="laundry-schedules")
router.register("events", LaundryEventViewSet, basename="laundry-events")
router.register("room-ranges", LaundryRoomRangeViewSet, basename="laundry-room-ranges")

urlpatterns = router.urls
