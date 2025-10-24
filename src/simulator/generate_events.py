"""Generate streaming retail purchase events and upload to S3 in small NDJSON files."""
import json
import time
import uuid
import random
import argparse
from datetime import datetime, timezone
import boto3

PRODUCTS = [
    {"product_id": "P100", "category": "electronics", "price": 199.99},
    {"product_id": "P101", "category": "clothing", "price": 29.99},
    {"product_id": "P102", "category": "home", "price": 49.99},
    {"product_id": "P103", "category": "grocery", "price": 3.49},
]

def random_event():
    p = random.choice(PRODUCTS)
    qty = random.randint(1, 5)
    total = round(p["price"] * qty, 2)
    return {
        "event_id": str(uuid.uuid4()),
        "ts": datetime.now(timezone.utc).isoformat(),
        "store_id": f"S{random.randint(1,10):03}",
        "customer_id": f"C{random.randint(1,5000):06}",
        "product_id": p["product_id"],
        "category": p["category"],
        "price": p["price"],
        "quantity": qty,
        "total_amount": total,
    }

def upload_batch(s3_client, bucket, prefix, batch_events):
    key = f"{prefix}/year={datetime.utcnow().strftime('%Y')}/month={datetime.utcnow().strftime('%m')}/day={datetime.utcnow().strftime('%d')}/{datetime.utcnow().strftime('%H%M%S')}_{uuid.uuid4().hex[:8]}.json"
    body = "\n".join(json.dumps(e) for e in batch_events)
    s3_client.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"))
    return key

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    parser.add_argument("--prefix", default="raw", help="S3 prefix, default 'raw'")
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--sleep", type=float, default=2.0, help="seconds between batches")
    args = parser.parse_args()

    s3 = boto3.client("s3")
    print("Starting simulator. Ctrl+C to stop.")
    try:
        while True:
            batch = [random_event() for _ in range(args.batch_size)]
            key = upload_batch(s3, args.bucket, args.prefix, batch)
            print(f"Uploaded {len(batch)} events to s3://{args.bucket}/{key}")
            time.sleep(args.sleep)
    except KeyboardInterrupt:
        print("Simulator stopped.")

if __name__ == '__main__':
    main()
