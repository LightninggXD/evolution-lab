"""
The icon bodies, split into four sets so they can be worked on independently.

Importing this package is what registers every icon into `iconkit.ICONS`; `make_icons.py` does
nothing but import it and render whatever turned up. A new set is a new module and one line here.
"""

from . import set_currency, set_action, set_item, set_place  # noqa: F401
from . import set_zone, set_ui  # noqa: F401
from . import set_relic  # noqa: F401
