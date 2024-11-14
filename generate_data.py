import sys
import uuid
import random
import json
import requests

from faker import Faker
import optional_faker as _
from datetime import date, datetime
import time


fake = Faker()

resorts = ["Vail", "Beaver Creek", "Breckenridge", "Keystone", "Crested Butte", "Park City", "Heavenly", "Northstar",
           "Kirkwood", "Whistler Blackcomb", "Perisher", "Falls Creek", "Hotham", "Stowe", "Mount Snow", "Okemo",
           "Hunter Mountain", "Mount Sunapee", "Attitash", "Wildcat", "Crotched", "Stevens Pass", "Liberty", "Roundtop",
           "Whitetail", "Jack Frost", "Big Boulder", "Alpine Valley", "Boston Mills", "Brandywine", "Mad River",
           "Hidden Valley", "Snow Creek", "Wilmot", "Afton Alps" , "Mt. Brighton", "Paoli Peaks"]

def generate_payload():

    url = 'http://localhost:8888/telemetry'

    state = fake.state_abbr()

    payload = {'txid': str(uuid.uuid4()),
               'rfid': hex(random.getrandbits(96)),
               'resort': fake.random_element(elements=resorts),
               'purchase_time': time.time(),
               'expiration_date': date(2023, 6, 1).isoformat(),
               'days': fake.random_int(min=1, max=7),
               'name': fake.name(),
               'address': fake.none_or({'street_address': fake.street_address(),
                                        'city': fake.city(), 'state': state,
                                        'postalcode': fake.postalcode_in_state(state)}),
               'phone': fake.none_or(fake.phone_number()),
               'email': fake.none_or(fake.email()),
               'emergency_contact': fake.none_or({'name': fake.name(), 'phone': fake.phone_number()}),
               }

    response = requests.post(url, json.dumps(payload) + '\n')


if __name__ == '__main__':
    args = sys.argv[1:]

    try:
        total_count = int(args[0])

    except IndexError:
        total_count = 1

    for _ in range(total_count):
        generate_payload()

    print('')