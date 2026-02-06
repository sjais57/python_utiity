def get_orchestra_auth_token(
    token_url: str,
    entitlements_token_field: str = "entitlements_token",
    metadata: Dict[str, Any] = None,
    request_id: str = None,
    username: str = None  # Add username as parameter
) -> str:
    """
    Fetch a JWT token from the Orchestra API using SPNEGO authentication.
    Returns only the token value (not the 'Bearer ' prefix).

    entitlements_token_field: the field name in the response containing the token
                              (default: 'entitlements_token')
    request_id: optional X-Request-ID header for traceability
    username: the authenticated user to generate token for (required)
    """

    if not username:
        logger.error("Username is required for Orchestra token generation")
        return None

    headers = {}
    if request_id:
        headers["X-Request-ID"] = request_id

    try:
        # Kinit before Orchestra token request
        import subprocess
        import os
        import pwd

        # Get UID for the specified username
        try:
            user_info = pwd.getpwnam(username)
            uid = user_info.pw_uid
        except KeyError:
            logger.error(f"User {username} not found on system")
            return None

        print(f"uid for user {username}: {uid}")

        # Use the provided username for keytab path
        keytabDir = f"/home/{username}/.secure"
        krb5ccname = f"FILE:/tmp/krb5cc_{uid}"

        # Set KRB5CCNAME environment variable
        os.environ["KRB5CCNAME"] = krb5ccname

        # Build kinit command for the specified user
        cmd = (
            f"kinit -k -t {keytabDir}/{username}.keytab "
            f"{username}@CORP.domain.COM -c {krb5ccname}"
        )

        logger.info(f"Running kinit command for user {username}: {cmd}")

        try:
            result = subprocess.run(
                cmd,
                shell=True,
                check=True,
                capture_output=True,
                text=True
            )
            logger.info(f"Kerberos ticket initialized successfully for {username}.")
        except subprocess.CalledProcessError as e:
            logger.error(
                f"Unable to initialize Kerberos ticket for user {username}. "
                f"Error: {e.stderr}. "
                "If the user has changed their SSO password, they need to run: "
                '("lab-setup.sh ssopasswd") or contact support.',
                exc_info=True
            )
            return None

        logger.info(
            f"Requesting Orchestra token from {token_url} "
            f"for user {username} with headers: {headers}"
        )

        resp = requests.get(
            token_url,
            auth=HTTPSPNEGOAuth(delegate=True),
            verify=False,
            headers=headers
        )

        logger.info(
            f"Orchestra response status: {resp.status_code}"
        )

        resp_json = resp.json()
        logger.debug(
            f"Orchestra response JSON: {resp_json}"
        )

        bearer_token = resp_json.get(entitlements_token_field)

        if bearer_token and bearer_token.startswith("ey"):
            logger.info(f"Successfully obtained Orchestra token (JWT) for {username}")
            return bearer_token

        if bearer_token and bearer_token.startswith("Bearer "):
            logger.info(f"Successfully obtained Orchestra token (Bearer) for {username}")
            return bearer_token.split(" ", 1)[1]

        logger.error(
            f"No valid token found in Orchestra response for user {username}. "
            f"Field: {entitlements_token_field}, "
            f"Response: {resp_json}"
        )
        return None

    except Exception as e:
        logger.exception(
            f"Error fetching Orchestra token from {token_url} for user {username}: {e}"
        )
        return None
