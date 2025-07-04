from fastapi import FastAPI, HTTPException, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from openai import OpenAI
from dotenv import load_dotenv
import os
import base64
import logging
import tempfile
import uuid
from datetime import datetime, timedelta
from typing import Optional
import aiofiles
from pathlib import Path
import uvicorn
import firebase_admin
from firebase_admin import credentials, firestore
from pydantic import BaseModel
from enum import Enum
import json
from io import BytesIO



# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('translator.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Initialize FastAPI app
app = FastAPI(
    title="Premium Voice Translator API",
    description="High-quality multi-language voice translation service",
    version="5.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# MARK: - Dynamic Model Configuration
class AudioModel(str, Enum):
    WHISPER_1 = "whisper-1"
    GPT4O_TRANSCRIBE = "gpt-4o-transcribe"
    GPT4O_MINI_TRANSCRIBE = "gpt-4o-mini-transcribe"

class TranslationModel(str, Enum):
    GPT4O = "gpt-4o"
    GPT4O_MINI = "gpt-4o-mini"
    GPT4_TURBO = "gpt-4-turbo"

class QualityTier(str, Enum):
    BASIC = "basic"           # whisper-1 + gpt-4o-mini
    PREMIUM = "premium"       # gpt-4o-transcribe + gpt-4o-mini  
    ULTRA = "ultra"          # gpt-4o-transcribe + gpt-4o

# Dynamic Configuration
class ModelConfig:
    def __init__(self):
        # Default: Premium tier for best balance
        self.audio_model = AudioModel.GPT4O_TRANSCRIBE
        self.translation_model = TranslationModel.GPT4O_MINI
        self.quality_tier = QualityTier.PREMIUM
        self.enable_prompting = True
        self.enable_fallback = True
        
    def set_tier(self, tier: QualityTier):
        """Set quality tier and adjust models accordingly"""
        self.quality_tier = tier
        if tier == QualityTier.BASIC:
            self.audio_model = AudioModel.WHISPER_1
            self.translation_model = TranslationModel.GPT4O_MINI
        elif tier == QualityTier.PREMIUM:
            self.audio_model = AudioModel.GPT4O_TRANSCRIBE
            self.translation_model = TranslationModel.GPT4O_MINI
        elif tier == QualityTier.ULTRA:
            self.audio_model = AudioModel.GPT4O_TRANSCRIBE
            self.translation_model = TranslationModel.GPT4O
            
    def get_cost_per_minute(self) -> float:
        """Calculate cost per minute based on current configuration"""
        audio_cost = {
            AudioModel.WHISPER_1: 0.006,
            AudioModel.GPT4O_TRANSCRIBE: 0.006,
            AudioModel.GPT4O_MINI_TRANSCRIBE: 0.003
        }
        
        # Translation cost is minimal for typical speech lengths
        translation_cost = {
            TranslationModel.GPT4O_MINI: 0.001,
            TranslationModel.GPT4O: 0.003,
            TranslationModel.GPT4_TURBO: 0.002
        }
        
        return audio_cost[self.audio_model] + translation_cost[self.translation_model]

# Global model configuration
model_config = ModelConfig()

# Configuration
class Config:
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    TEMP_DIR = Path(tempfile.gettempdir()) / "voice_translator"
    MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB for audio files
    MAX_RECORDING_MINUTES = 2.0  # 2 dakika maksimum kayıt
    
    # Premium Package Configuration
    PACKAGES = {
        "com.voicetranslator.starter": {"minutes": 300, "price": 9.99, "name": "Starter Pack"},
        "com.voicetranslator.popular": {"minutes": 900, "price": 24.99, "name": "Popular Pack"},
        "com.voicetranslator.professional": {"minutes": 1800, "price": 49.99, "name": "Professional Pack"},
        "com.voicetranslator.unlimited": {"minutes": -1, "price": 99.99, "name": "Unlimited Pack"}
    }
    
    # Free credits
    FREE_MINUTES = 30  # 30 dakika ücretsiz
    ADMIN_EMAIL = "admin@gmail.com"
    
    # Dynamic pricing based on model configuration
    @staticmethod
    def get_cost_per_minute():
        return model_config.get_cost_per_minute()

# Request/Response Models
class TranslationRequest(BaseModel):
    audio_base64: str
    user_id: str
    source_language: str = "tr"
    target_language: str = "en"
    source_language_name: str = "Turkish"
    target_language_name: str = "English"
    quality_tier: Optional[QualityTier] = QualityTier.PREMIUM

class TranslationResponse(BaseModel):
    success: bool
    source_text: str = ""
    target_text: str = ""
    source_language: str = ""
    target_language: str = ""
    duration_minutes: float = 0.0
    credits_used: float = 0.0
    model_used: str = ""
    quality_tier: str = ""
    error: Optional[str] = None
    user_credits: Optional[dict] = None

class ModelConfigRequest(BaseModel):
    audio_model: Optional[AudioModel] = None
    translation_model: Optional[TranslationModel] = None
    quality_tier: Optional[QualityTier] = None
    enable_prompting: Optional[bool] = None
    enable_fallback: Optional[bool] = None

class IAPRequest(BaseModel):
    user_id: str
    product_id: str
    transaction_id: str
    minutes: int
    package_type: str = ""

# Language mappings for TTS and prompting
TTS_LANGUAGE_MAP = {
    "en": "en-US", "tr": "tr-TR", "es": "es-ES", "fr": "fr-FR", "de": "de-DE",
    "it": "it-IT", "pt": "pt-PT", "ru": "ru-RU", "zh": "zh-CN", "ja": "ja-JP",
    "ko": "ko-KR", "ar": "ar-SA", "hi": "hi-IN", "af": "af-ZA", "sq": "sq-AL",
    "hy": "hy-AM", "az": "az-AZ", "be": "be-BY", "bs": "bs-BA", "bg": "bg-BG",
    "ca": "ca-ES", "hr": "hr-HR", "cs": "cs-CZ", "da": "da-DK", "nl": "nl-NL",
    "et": "et-EE", "fi": "fi-FI", "gl": "gl-ES", "ka": "ka-GE", "el": "el-GR",
    "he": "he-IL", "hu": "hu-HU", "is": "is-IS", "id": "id-ID", "kn": "kn-IN",
    "kk": "kk-KZ", "lv": "lv-LV", "lt": "lt-LT", "mk": "mk-MK", "ms": "ms-MY",
    "mr": "mr-IN", "mi": "mi-NZ", "ne": "ne-NP", "no": "no-NO", "fa": "fa-IR",
    "pl": "pl-PL", "ro": "ro-RO", "sr": "sr-RS", "sk": "sk-SK", "sl": "sl-SI",
    "sw": "sw-KE", "sv": "sv-SE", "tl": "tl-PH", "ta": "ta-IN", "th": "th-TH",
    "uk": "uk-UA", "ur": "ur-PK", "vi": "vi-VN", "cy": "cy-GB"
}






# Ensure temp directory exists
Config.TEMP_DIR.mkdir(exist_ok=True)

# Global variables
openai_client = None
db = None

# Initialize services
async def initialize_services():
    """Initialize OpenAI client"""
    global openai_client
    try:
        if Config.OPENAI_API_KEY:
            openai_client = OpenAI(api_key=Config.OPENAI_API_KEY)
            logger.info("OpenAI client initialized")
        else:
            logger.error("OpenAI API key not found")
            raise ValueError("OpenAI API key required")
    except Exception as e:
        logger.error(f"Failed to initialize OpenAI: {e}")
        raise

def initialize_firebase():
    """Initialize Firebase Admin SDK"""
    try:
        if not firebase_admin._apps:
            encoded = os.getenv("FIREBASE_CREDENTIALS")
            if not encoded:
                raise ValueError("FIREBASE_CREDENTIALS env var not found")

            decoded_bytes = base64.b64decode(encoded)
            cred_dict = json.load(BytesIO(decoded_bytes))
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
        
        global db
        db = firestore.client()
        logger.info("Firebase initialized")
    except Exception as e:
        logger.error(f"Firebase initialization failed: {e}")
        raise



@app.on_event("startup")
async def startup_event():
    """Application startup"""
    logger.info("Starting Premium Multi-Language Voice Translator API...")
    await initialize_services()
    initialize_firebase()
    logger.info(f"API started successfully with {model_config.quality_tier} quality tier!")

@app.on_event("shutdown")
async def shutdown_event():
    """Application shutdown"""
    logger.info("Shutting down Premium Voice Translator API...")
    
    # Cleanup temp files
    try:
        temp_files = list(Config.TEMP_DIR.glob("temp_*.wav"))
        for temp_file in temp_files:
            temp_file.unlink(missing_ok=True)
        logger.info(f"Cleaned up {len(temp_files)} temporary files")
    except Exception as e:
        logger.error(f"Error during cleanup: {e}")

    logger.info("Premium Voice Translator API shutdown complete")

# Utility functions
def generate_temp_filename(prefix: str = "temp") -> Path:
    """Generate unique temporary filename"""
    unique_id = str(uuid.uuid4())[:8]
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return Config.TEMP_DIR / f"{prefix}_{timestamp}_{unique_id}.wav"

async def save_audio_file(audio_bytes: bytes) -> Path:
    """Save audio bytes to temporary file"""
    temp_file = generate_temp_filename()
    
    try:
        async with aiofiles.open(temp_file, 'wb') as f:
            await f.write(audio_bytes)
        logger.info(f"Saved audio file: {temp_file}")
        return temp_file
    except Exception as e:
        logger.error(f"Failed to save audio file: {e}")
        raise HTTPException(status_code=500, detail="Failed to save audio file")

def cleanup_temp_file(file_path: Path):
    """Clean up temporary file"""
    try:
        if file_path.exists():
            file_path.unlink()
            logger.debug(f"Cleaned up: {file_path}")
    except Exception as e:
        logger.error(f"Error cleaning up {file_path}: {e}")

def estimate_audio_duration(audio_bytes: bytes) -> float:
    """Estimate audio duration in minutes from WAV bytes"""
    # Estimation: 44.1kHz, 16-bit, mono = 88200 bytes per second
    estimated_seconds = len(audio_bytes) / 88200
    return max(estimated_seconds / 60, 0.01)  # Minimum 0.01 minutes

def generate_transcription_prompt(source_language: str, source_language_name: str) -> str:
    """Generate intelligent prompt for better transcription quality"""
    if not model_config.enable_prompting:
        return ""
        
    prompts = {
        "tr": "Bu Türkçe bir konuşmadır. Lütfen noktalama işaretlerini doğru kullanın ve özel isimleri dikkatli yazın.",
        "en": "This is an English conversation. Please use proper punctuation and capitalization.",
        "es": "Esta es una conversación en español. Use puntuación y mayúsculas correctas.",
        "fr": "Ceci est une conversation en français. Utilisez la ponctuation et les majuscules appropriées.",
        "de": "Dies ist ein deutsches Gespräch. Verwenden Sie korrekte Interpunktion und Großschreibung.",
        "zh": "这是中文对话。请使用正确的标点符号。",
        "ja": "これは日本語の会話です。適切な句読点を使用してください。",
        "ar": "هذه محادثة باللغة العربية. يرجى استخدام علامات الترقيم المناسبة.",
    }
    
    return prompts.get(source_language, f"This is a conversation in {source_language_name}. Please use proper punctuation.")

async def transcribe_audio_premium(audio_file: Path, source_language: str, source_language_name: str) -> str:
    """Premium audio transcription with dynamic model selection"""
    
    try:
        with open(audio_file, "rb") as audio:
            if model_config.audio_model == AudioModel.WHISPER_1:
                # Using Whisper-1 for basic transcription
                logger.info(f"Using Whisper-1 for transcription")
                transcription = openai_client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio,
                    language=source_language,
                    response_format="text"
                )
                return transcription.strip()
                
            else:
                # Using GPT-4o transcribe models for premium quality
                logger.info(f"Using {model_config.audio_model} for transcription")
                
                # Generate intelligent prompt
                prompt = generate_transcription_prompt(source_language, source_language_name)
                
                transcription_params = {
                    "model": model_config.audio_model.value,
                    "file": audio,
                    "response_format": "text"
                }
                
                # Add prompt if supported
                if prompt and model_config.enable_prompting:
                    transcription_params["prompt"] = prompt
                
                transcription = openai_client.audio.transcriptions.create(**transcription_params)
                return transcription.strip()
                
    except Exception as e:
        logger.error(f"Transcription failed with {model_config.audio_model}: {e}")
        
        # Fallback to basic model if enabled
        if model_config.enable_fallback and model_config.audio_model != AudioModel.WHISPER_1:
            logger.info("Falling back to Whisper-1")
            try:
                with open(audio_file, "rb") as audio:
                    transcription = openai_client.audio.transcriptions.create(
                        model="whisper-1",
                        file=audio,
                        language=source_language,
                        response_format="text"
                    )
                    return transcription.strip()
            except Exception as fallback_error:
                logger.error(f"Fallback transcription also failed: {fallback_error}")
        
        raise e

async def translate_text_premium(text: str, source_lang: str, target_lang: str, 
                               source_lang_name: str, target_lang_name: str) -> str:
    """Premium text translation with dynamic model selection"""
    
    if source_lang == target_lang:
        return text
        
    try:
        logger.info(f"Using {model_config.translation_model} for translation")
        
        system_prompt = f"""You are a professional translator specializing in {source_lang_name} to {target_lang_name} translation.
Translate the text accurately while preserving:
- Original meaning and context
- Tone and style
- Technical terms appropriately
- Cultural nuances when relevant

Provide only the translation, no explanations."""

        user_prompt = f"Translate this {source_lang_name} text to {target_lang_name}:\n\n{text}"
        
        response = openai_client.chat.completions.create(
            model=model_config.translation_model.value,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            max_tokens=1000,
            temperature=0.1,
            top_p=0.9
        )
        
        translation = response.choices[0].message.content.strip()
        logger.info(f"Translation completed: {text[:50]}... → {translation[:50]}...")
        return translation
        
    except Exception as e:
        logger.error(f"Translation failed with {model_config.translation_model}: {e}")
        
        # Fallback to Google Translate if enabled
        if model_config.enable_fallback:
            logger.info("Falling back to Google Translate")
            try:
                from deep_translator import GoogleTranslator
                translator = GoogleTranslator(source=source_lang, target=target_lang)
                result = translator.translate(text)
                logger.info(f"Google translation: {text[:30]}... → {result[:30]}...")
                return result
            except Exception as fallback_error:
                logger.error(f"Google translation fallback failed: {fallback_error}")
        
        raise e

async def process_audio_translation(audio_bytes: bytes, request: TranslationRequest) -> TranslationResponse:
    """Process audio using premium models and return translation"""
    if not openai_client:
        raise HTTPException(status_code=503, detail="Translation service unavailable")
    
    # Set quality tier if specified
    if request.quality_tier:
        model_config.set_tier(request.quality_tier)
    
    # Check recording duration limit
    duration_minutes = estimate_audio_duration(audio_bytes)
    if duration_minutes > Config.MAX_RECORDING_MINUTES:
        return TranslationResponse(
            success=False,
            error=f"Recording too long. Maximum duration is {Config.MAX_RECORDING_MINUTES} minutes.",
            quality_tier=model_config.quality_tier.value
        )
    
    # Check credits and permissions
    credits = await get_user_credits(request.user_id)
    
    # Calculate cost based on current model configuration
    cost_minutes = duration_minutes * (Config.get_cost_per_minute() / 0.006)  # Normalize to base cost
    
    if not credits.get("is_admin", False) and not credits.get("is_unlimited", False):
        if credits.get("remaining_minutes", 0) < cost_minutes:
            return TranslationResponse(
                success=False,
                error="Insufficient credits. Please purchase a premium package.",
                user_credits=credits,
                quality_tier=model_config.quality_tier.value
            )
    
    temp_file = await save_audio_file(audio_bytes)
    
    try:
        # Step 1: Premium transcription
        source_text = await transcribe_audio_premium(
            temp_file, 
            request.source_language, 
            request.source_language_name
        )
        
        logger.info(f"Transcribed ({request.source_language_name}): {source_text}")
        
        # Step 2: Premium translation
        target_text = await translate_text_premium(
            source_text,
            request.source_language,
            request.target_language,
            request.source_language_name,
            request.target_language_name
        )
        
        # Deduct credits
        credits_used = 0.0
        if not credits.get("is_admin", False) and not credits.get("is_unlimited", False):
            await deduct_credits(request.user_id, cost_minutes)
            credits_used = cost_minutes

        # Get updated credits
        updated_credits = await get_user_credits(request.user_id)

        logger.info(f"Premium translation completed for user {request.user_id[:8]}...")
        logger.info(f"Models used: Audio={model_config.audio_model.value}, Translation={model_config.translation_model.value}")
        
        return TranslationResponse(
            success=True,
            source_text=source_text,
            target_text=target_text,
            source_language=request.source_language,
            target_language=request.target_language,
            duration_minutes=duration_minutes,
            credits_used=credits_used,
            model_used=f"{model_config.audio_model.value} + {model_config.translation_model.value}",
            quality_tier=model_config.quality_tier.value,
            user_credits=updated_credits
        )
        
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Premium translation failed: {e}")
        
        if "audio_too_short" in error_msg.lower():
            return TranslationResponse(
                success=False,
                error="Audio too short - please record for at least 0.5 seconds",
                user_credits=credits,
                quality_tier=model_config.quality_tier.value
            )
        else:
            return TranslationResponse(
                success=False,
                error=f"Translation failed: {error_msg}",
                user_credits=credits,
                quality_tier=model_config.quality_tier.value
            )
    finally:
        cleanup_temp_file(temp_file)

# Credit System Functions (keeping existing functions)
async def get_user_email_from_uid(user_id: str) -> str:
    """Firebase UID'den email adresini al"""
    try:
        from firebase_admin import auth
        user_record = auth.get_user(user_id)
        return user_record.email or ""
    except Exception as e:
        logger.error(f"Failed to get email for UID {user_id}: {e}")
        return ""

async def get_user_credits(user_id: str) -> dict:
    """Get user's current credit information"""
    try:
        user_doc = db.collection("users").document(user_id).get()
        
        if not user_doc.exists:
            # Yeni kullanıcı - email adresini kontrol et
            user_email = await get_user_email_from_uid(user_id)
            is_admin = user_email == Config.ADMIN_EMAIL
            
            initial_credits = {
                "email": user_email,
                "remaining_minutes": 999999 if is_admin else Config.FREE_MINUTES,
                "total_purchased_minutes": 999999 if is_admin else 0,
                "used_minutes": 0,
                "created_at": datetime.now(),
                "is_admin": is_admin,
                "is_premium": False,
                "is_unlimited": is_admin,
                "subscription_type": "unlimited" if is_admin else "free",
                "subscription_expiry": None
            }
            db.collection("users").document(user_id).set(initial_credits)
            logger.info(f"New user created: email={user_email}, admin={is_admin}")
            return {
                "user_id": user_id,
                **initial_credits
            }
        
        user_data = user_doc.to_dict()
        
        # Mevcut kullanıcı için admin kontrolü ve yeni alanları ekle
        if "email" not in user_data:
            user_email = await get_user_email_from_uid(user_id)
            is_admin = user_email == Config.ADMIN_EMAIL
            
            update_data = {
                "email": user_email,
                "is_admin": is_admin,
                "is_premium": user_data.get("is_premium", False),
                "is_unlimited": user_data.get("is_unlimited", is_admin),
                "subscription_type": user_data.get("subscription_type", "unlimited" if is_admin else "free"),
                "subscription_expiry": user_data.get("subscription_expiry", None)
            }
            
            db.collection("users").document(user_id).update(update_data)
            user_data.update(update_data)
        
        return {
            "user_id": user_id,
            "is_admin": user_data.get("is_admin", False),
            "is_premium": user_data.get("is_premium", False),
            "is_unlimited": user_data.get("is_unlimited", False),
            "remaining_minutes": user_data.get("remaining_minutes", 0),
            "total_purchased_minutes": user_data.get("total_purchased_minutes", 0),
            "used_minutes": user_data.get("used_minutes", 0),
            "subscription_type": user_data.get("subscription_type", "free"),
            "subscription_expiry": user_data.get("subscription_expiry", None)
        }
        
    except Exception as e:
        logger.error(f"Get user credits failed: {e}")
        return {"user_id": user_id, "remaining_minutes": 0, "error": str(e)}

async def deduct_credits(user_id: str, minutes_used: float) -> bool:
    """Deduct credits from user account"""
    try:
        user_ref = db.collection("users").document(user_id)
        user_doc = user_ref.get()
        
        if not user_doc.exists:
            logger.warning(f"User {user_id} not found for credit deduction")
            return False
        
        user_data = user_doc.to_dict()
        
        # Admin ve unlimited kontrolü
        if user_data.get("is_admin", False) or user_data.get("is_unlimited", False):
            logger.info(f"Unlimited user {user_id} - no credit deduction")
            return True
            
        current_remaining = user_data.get("remaining_minutes", 0)
        
        if current_remaining < minutes_used:
            logger.warning(f"Insufficient credits for {user_id}: {current_remaining} < {minutes_used}")
            return False
        
        # Update credits
        new_remaining = current_remaining - minutes_used
        new_used = user_data.get("used_minutes", 0) + minutes_used
        
        user_ref.update({
            "remaining_minutes": new_remaining,
            "used_minutes": new_used,
            "last_used": datetime.now()
        })
        
        # Log usage with model info
        db.collection("usage_logs").add({
            "user_id": user_id,
            "minutes_used": minutes_used,
            "remaining_after": new_remaining,
            "timestamp": datetime.now(),
            "type": "translation",
            "audio_model": model_config.audio_model.value,
            "translation_model": model_config.translation_model.value,
            "quality_tier": model_config.quality_tier.value
        })
        
        logger.info(f"Deducted {minutes_used:.3f} minutes from user. Remaining: {new_remaining:.2f}")
        return True
        
    except Exception as e:
        logger.error(f"Credit deduction failed: {e}")
        return False

async def add_credits(user_id: str, minutes_to_add: int, package_type: str = "") -> bool:
    """Add credits to user account"""
    try:
        user_ref = db.collection("users").document(user_id)
        user_doc = user_ref.get()
        
        is_unlimited = minutes_to_add == -1
        
        if not user_doc.exists:
            # Create new user
            user_ref.set({
                "remaining_minutes": 999999 if is_unlimited else minutes_to_add,
                "total_purchased_minutes": 999999 if is_unlimited else minutes_to_add,
                "used_minutes": 0,
                "created_at": datetime.now(),
                "is_admin": False,
                "is_premium": True,
                "is_unlimited": is_unlimited,
                "subscription_type": "unlimited" if is_unlimited else "premium",
                "subscription_expiry": None if is_unlimited else (datetime.now() + timedelta(days=365)).isoformat()
            })
        else:
            user_data = user_doc.to_dict()
            
            if is_unlimited:
                # Unlimited package
                user_ref.update({
                    "remaining_minutes": 999999,
                    "total_purchased_minutes": user_data.get("total_purchased_minutes", 0) + 999999,
                    "is_premium": True,
                    "is_unlimited": True,
                    "subscription_type": "unlimited",
                    "subscription_expiry": None
                })
            else:
                # Regular package
                user_ref.update({
                    "remaining_minutes": user_data.get("remaining_minutes", 0) + minutes_to_add,
                    "total_purchased_minutes": user_data.get("total_purchased_minutes", 0) + minutes_to_add,
                    "is_premium": True,
                    "is_unlimited": False,
                    "subscription_type": "premium",
                    "subscription_expiry": (datetime.now() + timedelta(days=365)).isoformat()
                })
        
        # Log purchase
        db.collection("purchase_logs").add({
            "user_id": user_id,
            "minutes_added": minutes_to_add,
            "package_type": package_type,
            "is_unlimited": is_unlimited,
            "timestamp": datetime.now()
        })
        
        logger.info(f"Added {minutes_to_add if minutes_to_add != -1 else 'unlimited'} minutes to user ({package_type})")
        return True
        
    except Exception as e:
        logger.error(f"Add credits failed: {e}")
        return False

# API Routes
@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "message": "Premium Multi-Language Voice Translator API",
        "status": "running",
        "version": "5.0.0",
        "timestamp": datetime.now().isoformat(),
        "current_config": {
            "audio_model": model_config.audio_model.value,
            "translation_model": model_config.translation_model.value,
            "quality_tier": model_config.quality_tier.value,
            "cost_per_minute": model_config.get_cost_per_minute(),
            "prompting_enabled": model_config.enable_prompting,
            "fallback_enabled": model_config.enable_fallback
        },
        "features": {
            "languages_supported": len(TTS_LANGUAGE_MAP),
            "premium_packages": len(Config.PACKAGES),
            "max_recording_minutes": Config.MAX_RECORDING_MINUTES,
            "dynamic_model_switching": True
        },
        "services": {
            "openai": openai_client is not None,
            "firebase": db is not None
        }
    }

@app.get("/health")
async def health_check():
    """Detailed health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "services": {
            "openai_api": openai_client is not None,
            "firebase": db is not None
        },
        "models": {
            "audio": model_config.audio_model.value,
            "translation": model_config.translation_model.value,
            "tier": model_config.quality_tier.value
        }
    }

@app.get("/config")
async def get_model_config():
    """Get current model configuration"""
    return {
        "audio_model": model_config.audio_model.value,
        "translation_model": model_config.translation_model.value,
        "quality_tier": model_config.quality_tier.value,
        "cost_per_minute": model_config.get_cost_per_minute(),
        "enable_prompting": model_config.enable_prompting,
        "enable_fallback": model_config.enable_fallback,
        "available_models": {
            "audio": [model.value for model in AudioModel],
            "translation": [model.value for model in TranslationModel],
            "quality_tiers": [tier.value for tier in QualityTier]
        }
    }

@app.post("/config")
async def update_model_config(config_request: ModelConfigRequest):
    """Update model configuration dynamically"""
    try:
        if config_request.quality_tier:
            model_config.set_tier(config_request.quality_tier)
            
        if config_request.audio_model:
            model_config.audio_model = config_request.audio_model
            
        if config_request.translation_model:
            model_config.translation_model = config_request.translation_model
            
        if config_request.enable_prompting is not None:
            model_config.enable_prompting = config_request.enable_prompting
            
        if config_request.enable_fallback is not None:
            model_config.enable_fallback = config_request.enable_fallback
            
        logger.info(f"Model configuration updated: {model_config.quality_tier.value}")
        
        return {
            "success": True,
            "message": "Configuration updated successfully",
            "new_config": {
                "audio_model": model_config.audio_model.value,
                "translation_model": model_config.translation_model.value,
                "quality_tier": model_config.quality_tier.value,
                "cost_per_minute": model_config.get_cost_per_minute(),
                "enable_prompting": model_config.enable_prompting,
                "enable_fallback": model_config.enable_fallback
            }
        }
        
    except Exception as e:
        logger.error(f"Failed to update configuration: {e}")
        raise HTTPException(status_code=400, detail=f"Configuration update failed: {str(e)}")

@app.get("/languages")
async def get_supported_languages():
    """Get list of supported languages"""
    return {
        "supported_languages": list(TTS_LANGUAGE_MAP.keys()),
        "language_map": TTS_LANGUAGE_MAP,
        "total_count": len(TTS_LANGUAGE_MAP)
    }

# Main Translation Endpoint
@app.post("/api/translate", response_model=TranslationResponse)
async def translate_audio(request: TranslationRequest):
    """Translate audio from base64 encoded data using premium models"""
    try:
        # Validate languages
        if request.source_language not in TTS_LANGUAGE_MAP:
            raise HTTPException(status_code=400, detail=f"Unsupported source language: {request.source_language}")
        
        if request.target_language not in TTS_LANGUAGE_MAP:
            raise HTTPException(status_code=400, detail=f"Unsupported target language: {request.target_language}")
        
        # Decode base64 audio
        try:
            audio_bytes = base64.b64decode(request.audio_base64)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid base64 audio data: {str(e)}")
        
        # Validate file size
        if len(audio_bytes) > Config.MAX_FILE_SIZE:
            raise HTTPException(
                status_code=413, 
                detail=f"Audio file too large. Maximum size: {Config.MAX_FILE_SIZE // (1024 * 1024)}MB"
            )
        
        # Process translation with premium models
        result = await process_audio_translation(audio_bytes, request)
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Translation API error: {e}")
        raise HTTPException(status_code=500, detail=f"Translation failed: {str(e)}")

# Alternative endpoint using file upload
@app.post("/api/translate-file", response_model=TranslationResponse)
async def translate_audio_file(
    file: UploadFile = File(...),
    user_id: str = Form(...),
    source_language: str = Form("tr"),
    target_language: str = Form("en"),
    source_language_name: str = Form("Turkish"),
    target_language_name: str = Form("English"),
    quality_tier: QualityTier = Form(QualityTier.PREMIUM)
):
    """Translate audio from uploaded file using premium models"""
    try:
        # Validate file type
        if not file.content_type or not file.content_type.startswith('audio/'):
            raise HTTPException(status_code=400, detail="File must be an audio file")
        
        # Read file content
        audio_bytes = await file.read()
        
        # Validate file size
        if len(audio_bytes) > Config.MAX_FILE_SIZE:
            raise HTTPException(
                status_code=413, 
                detail=f"Audio file too large. Maximum size: {Config.MAX_FILE_SIZE // (1024 * 1024)}MB"
            )
        
        # Create request object
        request = TranslationRequest(
            audio_base64=base64.b64encode(audio_bytes).decode(),
            user_id=user_id,
            source_language=source_language,
            target_language=target_language,
            source_language_name=source_language_name,
            target_language_name=target_language_name,
            quality_tier=quality_tier
        )
        
        # Process translation
        result = await process_audio_translation(audio_bytes, request)
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"File translation API error: {e}")
        raise HTTPException(status_code=500, detail=f"Translation failed: {str(e)}")

# Credits API endpoints
@app.get("/api/credits/{user_id}")
async def get_credits(user_id: str):
    """Get user's credit information"""
    try:
        credits = await get_user_credits(user_id)
        return credits
    except Exception as e:
        logger.error(f"Get credits API error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get credits")

@app.post("/api/add-credits")
async def add_credits_iap(request: IAPRequest):
    """Add credits from iOS In-App Purchase"""
    try:
        user_id = request.user_id
        product_id = request.product_id
        transaction_id = request.transaction_id
        minutes = request.minutes
        package_type = request.package_type

        if not all([user_id, product_id, transaction_id]):
            raise HTTPException(status_code=400, detail="Missing required fields")
        
        # Validate product ID
        if product_id not in Config.PACKAGES:
            raise HTTPException(status_code=400, detail=f"Invalid product ID: {product_id}")
        
        # Check if transaction already processed
        existing_transaction = db.collection("iap_transactions").document(str(transaction_id)).get()
        if existing_transaction.exists:
            logger.warning(f"Transaction {transaction_id} already processed")
            return {"success": False, "message": "Transaction already processed"}
        
        # Add credits to user
        success = await add_credits(user_id, minutes, package_type)
        
        if success:
            # Record transaction
            db.collection("iap_transactions").document(str(transaction_id)).set({
                "user_id": user_id,
                "product_id": product_id,
                "transaction_id": transaction_id,
                "minutes_added": minutes,
                "package_type": package_type,
                "timestamp": datetime.now(),
                "platform": "ios"
            })
            
            updated_credits = await get_user_credits(user_id)
            logger.info(f"IAP: Added {minutes if minutes != -1 else 'unlimited'} minutes via {product_id}")
            
            return {
                "success": True,
                "message": f"Successfully added {package_type}",
                "credits": updated_credits
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to add credits")
        
    except Exception as e:
        logger.error(f"IAP credit addition failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Analytics endpoints
@app.get("/api/analytics/usage/{user_id}")
async def get_user_usage_analytics(user_id: str):
    """Get user usage analytics with model information"""
    try:
        # Get usage logs
        usage_logs = db.collection("usage_logs").where("user_id", "==", user_id).limit(100).get()
        
        total_translations = len(usage_logs)
        total_minutes_used = sum([log.to_dict().get("minutes_used", 0) for log in usage_logs])
        
        # Get purchase history
        purchases = db.collection("purchase_logs").where("user_id", "==", user_id).get()
        
        # Analyze model usage
        model_usage = {}
        for log in usage_logs:
            log_data = log.to_dict()
            audio_model = log_data.get("audio_model", "unknown")
            model_usage[audio_model] = model_usage.get(audio_model, 0) + 1
        
        return {
            "user_id": user_id,
            "total_translations": total_translations,
            "total_minutes_used": round(total_minutes_used, 2),
            "total_purchases": len(purchases),
            "average_session_length": round(total_minutes_used / max(total_translations, 1), 2),
            "model_usage": model_usage,
            "current_tier": model_config.quality_tier.value
        }
    except Exception as e:
        logger.error(f"Analytics error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get analytics")

@app.get("/api/analytics/system")
async def get_system_analytics():
    """Get system-wide analytics"""
    try:
        # Get recent usage logs
        recent_logs = db.collection("usage_logs").limit(1000).get()
        
        # Model usage statistics
        model_stats = {}
        total_minutes = 0
        
        for log in recent_logs:
            log_data = log.to_dict()
            audio_model = log_data.get("audio_model", "unknown")
            translation_model = log_data.get("translation_model", "unknown")
            minutes = log_data.get("minutes_used", 0)
            
            key = f"{audio_model}+{translation_model}"
            if key not in model_stats:
                model_stats[key] = {"count": 0, "total_minutes": 0}
            
            model_stats[key]["count"] += 1
            model_stats[key]["total_minutes"] += minutes
            total_minutes += minutes
        
        return {
            "total_translations": len(recent_logs),
            "total_minutes_processed": round(total_minutes, 2),
            "model_usage_stats": model_stats,
            "current_config": {
                "audio_model": model_config.audio_model.value,
                "translation_model": model_config.translation_model.value,
                "quality_tier": model_config.quality_tier.value
            },
            "average_cost_per_minute": model_config.get_cost_per_minute()
        }
    except Exception as e:
        logger.error(f"System analytics error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get system analytics")

# Error handlers
@app.exception_handler(404)
async def not_found_handler(request, exc):
    return JSONResponse(
        status_code=404,
        content={"error": "Endpoint not found"}
    )

@app.exception_handler(500)
async def internal_error_handler(request, exc):
    logger.error(f"Internal server error: {exc}")
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error"}
    )

# Main execution
if __name__ == "__main__":
    import socket
    
    def get_local_ip():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"
    
    local_ip = get_local_ip()
    print(f"🌐 Premium Translation API Server starting on: http://{local_ip}:8000")
    print(f"📱 iOS device should connect to: {local_ip}:8000")
    print(f"📖 API Documentation: http://{local_ip}:8000/docs")
    print(f"🌍 Supported Languages: {len(TTS_LANGUAGE_MAP)}")
    print(f"💎 Premium Packages: {len(Config.PACKAGES)}")
    print(f"⏱️ Max Recording: {Config.MAX_RECORDING_MINUTES} minutes")
    print(f"🤖 Audio Model: {model_config.audio_model.value}")
    print(f"🔤 Translation Model: {model_config.translation_model.value}")
    print(f"⭐ Quality Tier: {model_config.quality_tier.value}")
    print(f"💰 Cost per minute: ${model_config.get_cost_per_minute():.4f}")
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info",
        access_log=True
    )