import threading
import datetime

def __init__(self, ...):
    ...
    # Token management
    self.current_token = None
    self.token_expiry_time = None
    self.token_refresh_buffer = 300  # 5 minutes before expiry
    self._token_lock = threading.Lock()


def generate_token(self):
    auth_url = f"{self.api_root}/project/auth/token"

    payload = {
        "username": getpass.getuser(),
        "password": ssoDecryption()
    }

    headers = {"Content-Type": "application/json"}

    response = requests.post(auth_url, json=payload, headers=headers)
    response.raise_for_status()

    data = response.json()

    access_token = data.get("access_token")

    # If API provides expires_in, use it; else default to 1 hour
    expires_in = data.get("expires_in", 3600)

    self.current_token = access_token
    self.token_expiry_time = (
        datetime.datetime.now() +
        datetime.timedelta(seconds=expires_in)
    )

    return access_token

def get_valid_token(self):
    """
    Returns a valid token.
    Refreshes automatically if expired or about to expire.
    """
    logger = get_logger('llm4mdd', FRMT=self.FRMT, console=True)

    with self._token_lock:
        if (
            self.current_token is None or
            self.token_expiry_time is None or
            datetime.datetime.now() >=
            self.token_expiry_time - datetime.timedelta(seconds=self.token_refresh_buffer)
        ):
            logger.info("Token expired or near expiry. Refreshing token...")
            return self.generate_token()

        return self.current_token


def call_llm_endpoint(self, url, payload):
    headers = {
        "Authorization": f"Bearer {self.get_valid_token()}",
        "Content-Type": "application/json"
    }

    response = requests.post(url, json=payload, headers=headers)

    if response.status_code == 401:
        logger.warning("401 Unauthorized. Refreshing token and retrying once.")

        with self._token_lock:
            self.current_token = None

        headers["Authorization"] = f"Bearer {self.get_valid_token()}"
        response = requests.post(url, json=payload, headers=headers)

    response.raise_for_status()
    return response.json()

#Step 6: Update process_doc() safely
if self.purpose == 'rewrite':
    logger.info("Getting valid token for create prompt")
    access_token = self.get_valid_token()

    logger.info("Creating Prompts...")
    self.create_prompts_rewrite_para_by_para()

    logger.info("Getting valid token for creating response")
    access_token = self.get_valid_token()

    logger.info("Creating Responses...")
    self.create_responses()
