from django.urls import path

# Import view classes and viewsets
from .views import (AddAdminView,RegisterView,ApproveUserView,Myprofile,RoleManagementView,EmployerCommandeRoleUpdateView,CaisseSessionViewSet,CaisseMovementViewSet,AdminMagasinOverviewView,UsersByMagasinView,LogoutEventView,MagasinStatsView,DashboardView,ApiEndpointsListView,PendingUsersView,DeleteUserView,RejectUserView,ChangePasswordView,NotificationViewSet,MagasinViewSet,ChatUsersListView,ChatMessageHistoryView,TransferProductsView,BackupExportView,BackupImportView,PublicForgotPasswordRequestView,PublicForgotPasswordStatusView,PublicForgotPasswordConfirmView,EmployeePasswordResetListView,EmployeePasswordResetResolveView,
)

from rest_framework_simplejwt.views import TokenViewBase
from .authentication import CustomTokenObtainPairSerializer, CustomTokenRefreshSerializer
from rest_framework.routers import DefaultRouter

router = DefaultRouter()
router.register(r"caisse/sessions", CaisseSessionViewSet, basename="caisse-sessions")
router.register(r"caisse/movements", CaisseMovementViewSet, basename="caisse-movements")
router.register(r"notifications", NotificationViewSet, basename="notifications")
router.register(r"magasins", MagasinViewSet, basename="magasins")

class CustomLoginView(TokenViewBase):
    serializer_class = CustomTokenObtainPairSerializer

class CustomTokenRefreshView(TokenViewBase):
    serializer_class = CustomTokenRefreshSerializer

urlpatterns = [
    # Auth
    path("login/", CustomLoginView.as_view()),
    path("refresh/", CustomTokenRefreshView.as_view()),
    # Register
    path("register/", RegisterView.as_view()),
    # My profile
    path("me/", Myprofile.as_view()),
    # Approve user
    path("approve/<int:user_id>/", ApproveUserView.as_view()),
    # Role management
    path("role/<int:user_id>/", RoleManagementView.as_view()),
    path("employers/<int:user_id>/commande-role/", EmployerCommandeRoleUpdateView.as_view()),
    # List of users grouped by magasin
    path("magasins/users/", UsersByMagasinView.as_view()),
    # Best-effort logout timestamp (explicit "Déconnexion" click)
    path("logout-event/", LogoutEventView.as_view()),
    # Store statistics by magasin
    path("magasins/stats/", MagasinStatsView.as_view()),
    # Overview détaillée des magasins pour l'admin
    path("magasins/overview/", AdminMagasinOverviewView.as_view()),
    # Dashboard stats
    path("dashboard/", DashboardView.as_view()),
    # Pending users (awaiting approval)
    path("change-password/", ChangePasswordView.as_view()),
    path("pending/", PendingUsersView.as_view()),
    # Transfer products between stores
    path("transfer/products/", TransferProductsView.as_view()),
    # Backup: export/import full database + media (admin only)
    path("backup/export/", BackupExportView.as_view()),
    path("backup/import/", BackupImportView.as_view()),
    # Delete user
    path("delete/<int:user_id>/", DeleteUserView.as_view()),
    # Reject user
    path("reject/<int:user_id>/", RejectUserView.as_view()),
    # Explore endpoints
    path("endpoints/", ApiEndpointsListView.as_view()),
    # Chat endpoints
    path("chat/users/", ChatUsersListView.as_view()),
    path("chat/history/", ChatMessageHistoryView.as_view()),
    path('add-admin/', AddAdminView.as_view(), name='add-admin'),
    # Employee (magasin/employer) password reset requests — resolved by their admin
    path("password-reset-requests/", EmployeePasswordResetListView.as_view()),
    path("password-reset-requests/<int:request_id>/", EmployeePasswordResetResolveView.as_view()),
    # Public (unauthenticated — forgot password)
    path("public/forgot-password/", PublicForgotPasswordRequestView.as_view()),
    path("public/forgot-password/status/", PublicForgotPasswordStatusView.as_view()),
    path("public/forgot-password/confirm/", PublicForgotPasswordConfirmView.as_view()),
] + router.urls
