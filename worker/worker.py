# import redis
# import time
# import os
# import signal

# r = redis.Redis(host="redis-server", port=6379)

# def process_job(job_id):
#     print(f"Processing job {job_id}")
#     time.sleep(2)  # simulate work
#     r.hset(f"job:{job_id}", "status", "completed")
#     print(f"Done: {job_id}")

# while True:
#     job = r.brpop("job", timeout=5)
#     if job:
#         _, job_id = job
#         process_job(job_id.decode())

import redis
import time
import signal
import os

r = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis-server"),
    port=int(os.environ.get("REDIS_PORT", 6379)),
    password=os.environ.get("REDIS_PASSWORD"),
)

shutdown_requested = False


def handle_shutdown(signum, frame):
    global shutdown_requested
    print(f"Received signal {signum}, finishing current job then shutting down...")
    shutdown_requested = True


signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)


def process_job(job_id):
    print(f"Processing job {job_id}")
    time.sleep(2)  # simulate work
    r.hset(f"job:{job_id}", "status", "completed")
    print(f"Done: {job_id}")


print("Worker started")
while not shutdown_requested:
    try:
        job = r.brpop("job", timeout=5)
        if not job:
            continue  # timeout, loop back and check shutdown flag

        _, job_id = job
        job_id = job_id.decode()

        try:
            process_job(job_id)
        except Exception as e:
            # Job-level error: mark as failed, keep worker alive
            print(f"Error processing job {job_id}: {e}")
            try:
                r.hset(f"job:{job_id}", "status", "failed")
                r.hset(f"job:{job_id}", "error", str(e))
            except redis.RedisError as redis_err:
                print(f"Could not update job status in Redis: {redis_err}")

    except redis.ConnectionError as e:
        # Redis is down: wait and retry, don't crash
        print(f"Redis connection error: {e}. Retrying in 5 seconds...")
        time.sleep(5)

    except redis.RedisError as e:
        # Other Redis errors (timeouts, etc.)
        print(f"Redis error: {e}. Retrying in 1 second...")
        time.sleep(1)

    except Exception as e:
        # Catch-all for truly unexpected errors
        print(f"Unexpected error in worker loop: {e}")
        time.sleep(1)

print("Worker shut down gracefully")
