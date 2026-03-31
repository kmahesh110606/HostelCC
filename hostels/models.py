from django.db import models


class HostelBlock(models.Model):
    class BlockName(models.TextChoices):
        A = "A", "A"
        B = "B", "B"
        C = "C", "C"
        D1 = "D1", "D1"
        D2 = "D2", "D2"
        E = "E", "E"

    block_name = models.CharField(max_length=2, choices=BlockName.choices, unique=True, db_index=True)

    def __str__(self) -> str:
        return self.block_name


class Room(models.Model):
    room_no = models.CharField(max_length=10)
    capacity = models.PositiveIntegerField(default=1)
    block = models.ForeignKey(HostelBlock, on_delete=models.CASCADE, related_name="rooms")

    class Meta:
        unique_together = ("block", "room_no")

    def __str__(self) -> str:
        return f"{self.block.block_name}-{self.room_no}"
