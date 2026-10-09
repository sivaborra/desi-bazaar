"""Synthetic seed data for the vertical slice. No real PII (IC-3)."""

USERS = {
    # buyers
    "buyer-rohan": {"id": "buyer-rohan", "role": "buyer", "name": "Rohan Mehta", "phone": "+46700000001"},
    "buyer-sara": {"id": "buyer-sara", "role": "buyer", "name": "Sara Khan", "phone": "+46700000002"},
    # sellers
    "seller-anaya": {"id": "seller-anaya", "role": "seller", "name": "Anaya Sharma",
                     "status": "approved", "badge_scope": "ID verified", "badge_date": "2026-10-01",
                     "swish_recipient": "+46700000101"},
    "seller-priya": {"id": "seller-priya", "role": "seller", "name": "Priya Nair",
                     "status": "pending", "badge_scope": None, "badge_date": None,
                     "swish_recipient": None},
    # admin
    "admin-1": {"id": "admin-1", "role": "admin", "name": "Ops Admin", "phone": "+46700000999"},
}

LISTINGS = {
    "listing-saree": {
        "id": "listing-saree", "seller_id": "seller-anaya",
        "category": "saree", "condition": "new", "size_text": "6.3m, blouse 38",
        "defect_disclosure": None, "price_sek": 850,
        "units": ["unit-saree-1", "unit-saree-2"],   # two physical units
    },
    "listing-kurti": {
        "id": "listing-kurti", "seller_id": "seller-anaya",
        "category": "kurti", "condition": "pre-loved",
        "size_text": "M, length 110cm", "defect_disclosure": "Small stain near hem, see photo 3",
        "price_sek": 220, "units": ["unit-kurti-1"],
    },
    "listing-sherwani": {
        "id": "listing-sherwani", "seller_id": "seller-priya",   # pending seller
        "category": "sherwani", "condition": "new",
        "size_text": "42", "defect_disclosure": None,
        "price_sek": 2400, "units": ["unit-sherwani-1"],
    },
}

# One active promotion so the Flutter track sees promoted ranking immediately (SC-1).
SEED_PROMOTIONS = [
    {"listing_id": "listing-saree", "seller_id": "seller-anaya", "days": 3},
]
