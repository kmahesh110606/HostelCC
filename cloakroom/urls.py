from rest_framework.routers import DefaultRouter

from .views import CloakroomEntryViewSet

router = DefaultRouter()
router.register("entries", CloakroomEntryViewSet, basename="cloakroom-entries")

urlpatterns = router.urls
