from rest_framework.routers import DefaultRouter

from .views import LaundryEventViewSet, LaundryScheduleViewSet

router = DefaultRouter()
router.register("schedules", LaundryScheduleViewSet, basename="laundry-schedules")
router.register("events", LaundryEventViewSet, basename="laundry-events")

urlpatterns = router.urls
