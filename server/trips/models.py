from django.db import models
import uuid
from django.contrib.auth import get_user_model
from django.conf import settings
from django.utils.translation import ugettext_lazy as _

class Trip(models.Model):

    class Transitions(models.TextChoices):
        REQUESTED = ('REQUESTED', 'requested')
        STARTED = ('STARTED', 'started')
        IN_PROGRESS = ('IN_PROGRESS', 'in_progress')
        COMPLETED = ('COMPLETED', 'completed')
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    pickup = models.CharField(_("Pickup Address"), max_length=255)
    dropoff = models.CharField(_("Drop-off Address"), max_length=255)
    status = models.CharField(_("Trips Status"), max_length=20, choices=Transitions.choices, default=Transitions.REQUESTED)
    created = models.DateTimeField(_("Trip Created On"), auto_now_add=True)
    updated = models.DateTimeField(_("Trip Updated On"), auto_now=True)

    def get_absolute_url(self):
        return reverse("trip:trip-detail", kwargs={"id": self.id})
    

    def __str__(self):
        return self.id
    
    

    


