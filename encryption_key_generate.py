import base64
import hashlib
import os
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2
from cryptography.hazmat.backends import default_backend

def encrypt_api_key(password, api_key):
    """Example of how Artifactory might encrypt an API key"""
    # Generate random salt
    salt = os.urandom(16)
    
    # Derive key using PBKDF2 (similar to Artifactory)
    kdf = PBKDF2(
        algorithm=hashlib.sha256(),
        length=32,
        salt=salt,
        iterations=10000,
        backend=default_backend()
    )
    key = kdf.derive(password.encode())
    
    # Generate IV
    iv = os.urandom(16)
    
    # Encrypt with AES-256-CBC
    cipher = Cipher(
        algorithms.AES(key),
        modes.CBC(iv),
        backend=default_backend()
    )
    encryptor = cipher.encryptor()
    
    # Pad the API key to block size
    padded_api_key = api_key.encode() + b'\x00' * (16 - len(api_key) % 16)
    encrypted = encryptor.update(padded_api_key) + encryptor.finalize()
    
    # Return in Artifactory-like format
    return {
        "encryptedValue": base64.b64encode(iv + encrypted).decode(),
        "salt": base64.b64encode(salt).decode()
    }

# This is for understanding only - use Artifactory's built-in mechanisms
