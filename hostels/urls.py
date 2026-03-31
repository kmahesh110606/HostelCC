from rest_framework.routers import DefaultRouter

from .views import HostelBlockViewSet, RoomViewSet

router = DefaultRouter()
router.register("blocks", HostelBlockViewSet, basename="blocks")
router.register("rooms", RoomViewSet, basename="rooms")

urlpatterns = router.urls
