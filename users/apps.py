from django.apps import AppConfig


class UsersConfig(AppConfig):
    name = 'users'
    def ready(self):
        # import signal handlers
        try:
            import users.signals  # noqa: F401
        except Exception:
            pass
