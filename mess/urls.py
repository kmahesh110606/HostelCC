from rest_framework.routers import DefaultRouter

from .views import (
	CatererViewSet,
	FeedbackViewSet,
	MessChangeRequestViewSet,
	MessMenuViewSet,
	NightMessLogViewSet,
	PollViewSet,
)

router = DefaultRouter()
router.register("menu", MessMenuViewSet, basename="mess-menu")
router.register("caterers", CatererViewSet, basename="mess-caterers")
router.register("feedback", FeedbackViewSet, basename="mess-feedback")
router.register("poll", PollViewSet, basename="mess-poll")
router.register("change", MessChangeRequestViewSet, basename="mess-change")
router.register("night-mess", NightMessLogViewSet, basename="night-mess")

urlpatterns = router.urls
