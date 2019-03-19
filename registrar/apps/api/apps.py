"""
Config for the api app.
"""
import analytics
from django.apps import AppConfig
from django.conf import settings


class ApiConfig(AppConfig):
    name = 'registrar.apps.api'
    verbose_name = 'API'

    def ready(self):
        """
        Initialize Segment analytics module by setting the write_key.
        """
        if settings.SEGMENT_KEY:
            analytics.write_key = settings.SEGMENT_KEY
