# from fastapi import FastAPI, UploadFile, File, WebSocket, WebSocketDisconnect, HTTPException
# from fastapi.middleware.cors import CORSMiddleware
# from fastapi.responses import JSONResponse
# from openai import OpenAI
# from dotenv import load_dotenv
# import os
# import whisper
# import json
# import base64
# import asyncio
# import logging
# import tempfile
# import uuid
# from datetime import datetime
# from typing import Dict, Optional
# import aiofiles
# from pathlib import Path
# import uvicorn
# from agent import TranslationAgent




# # Configure logging
# logging.basicConfig(
#     level=logging.INFO,
#     format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
# )
# logger = logging.getLogger(__name__)

# # Load environment variables
# load_dotenv()

# # Initialize FastAPI app
# app = FastAPI(
#     title="Professional Voice Translator API",
#     description="Real-time voice translation service with WebSocket support",
#     version="1.0.0",
#     docs_url="/docs",
#     redoc_url="/redoc"
# )

# # CORS middleware for mobile app compatibility
# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=["*"],  # In production, specify your mobile app domains
#     allow_credentials=True,
#     allow_methods=["*"],
#     allow_headers=["*"],
# )

# translation_agent = None


# # Global configurations
# class Config:
#     OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
#     TEMP_DIR = Path(tempfile.gettempdir()) / "voice_translator"
#     MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB
#     HEARTBEAT_INTERVAL = 30  # seconds
#     CONNECTION_TIMEOUT = 300  # seconds

# # Ensure temp directory exists
# Config.TEMP_DIR.mkdir(exist_ok=True)

# # Global variables
# active_connections: Dict[str, WebSocket] = {}
# whisper_model = None
# openai_client = None

# # Initialize services
# async def initialize_services():
#     """Initialize OpenAI client and Whisper model"""
#     global openai_client, whisper_model, translation_agent
    
#     try:
#         # Initialize OpenAI client
#         if Config.OPENAI_API_KEY:
#             openai_client = OpenAI(api_key=Config.OPENAI_API_KEY)
#             logger.info("✅ OpenAI client initialized")

#             # Initialize translation agent
#             translation_agent = TranslationAgent(openai_api_key=Config.OPENAI_API_KEY)
#             logger.info("✅ Translation agent initialized")
#         else:
#             logger.warning("⚠️ OpenAI API key not found - API mode disabled")
        
#         # Load Whisper model
#         logger.info("🔄 Loading Whisper LARGE model... (This may take a while)")
#         whisper_model = whisper.load_model("large")
#         logger.info("✅ Whisper LARGE model loaded successfully!")
        
#     except Exception as e:
#         logger.error(f"❌ Failed to initialize services: {e}")
#         raise

# @app.on_event("startup")
# async def startup_event():
#     """Application startup tasks"""
#     logger.info("🚀 Starting Voice Translator API...")
#     await initialize_services()
#     logger.info("✅ Voice Translator API started successfully!")

# @app.on_event("shutdown")
# async def shutdown_event():
#     """Application shutdown tasks"""
#     logger.info("🔄 Shutting down Voice Translator API...")
    
#     # Close all active WebSocket connections
#     for connection_id, websocket in list(active_connections.items()):
#         try:
#             await websocket.close(code=1000, reason="Server shutdown")
#             logger.info(f"Closed connection: {connection_id}")
#         except Exception as e:
#             logger.error(f"Error closing connection {connection_id}: {e}")
    
#     # Cleanup temp files
#     try:
#         temp_files = list(Config.TEMP_DIR.glob("temp_*.wav"))
#         for temp_file in temp_files:
#             temp_file.unlink(missing_ok=True)
#         logger.info(f"🧹 Cleaned up {len(temp_files)} temporary files")
#     except Exception as e:
#         logger.error(f"Error during cleanup: {e}")
    
#     logger.info("✅ Voice Translator API shutdown complete")

# # Utility functions
# def generate_temp_filename(prefix: str = "temp") -> Path:
#     """Generate unique temporary filename"""
#     unique_id = str(uuid.uuid4())[:8]
#     timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
#     return Config.TEMP_DIR / f"{prefix}_{timestamp}_{unique_id}.wav"

# async def save_audio_file(audio_bytes: bytes) -> Path:
#     """Save audio bytes to temporary file"""
#     temp_file = generate_temp_filename()
    
#     try:
#         async with aiofiles.open(temp_file, 'wb') as f:
#             await f.write(audio_bytes)
#         logger.info(f"💾 Saved audio file: {temp_file}")
#         return temp_file
#     except Exception as e:
#         logger.error(f"❌ Failed to save audio file: {e}")
#         raise HTTPException(status_code=500, detail="Failed to save audio file")

# def cleanup_temp_file(file_path: Path):
#     """Clean up temporary file"""
#     try:
#         if file_path.exists():
#             file_path.unlink()
#             logger.debug(f"🗑️ Cleaned up: {file_path}")
#     except Exception as e:
#         logger.error(f"Error cleaning up {file_path}: {e}")

# async def translate_with_google(text: str, source: str = 'tr', target: str = 'en') -> str:
#     """Translate text using Google Translator"""
#     try:
#         from deep_translator import GoogleTranslator
#         translator = GoogleTranslator(source=source, target=target)
#         result = translator.translate(text)
#         logger.info(f"🔄 Translated: {text[:50]}... → {result[:50]}...")
#         return result
#     except Exception as e:
#         logger.error(f"❌ Translation failed: {e}")
#         return text  # Return original text if translation fails

# async def process_audio_openai(audio_bytes: bytes) -> Dict[str, str]:
#     """Process audio using OpenAI Whisper API"""
#     if not openai_client:
#         raise HTTPException(status_code=503, detail="OpenAI API not available")
    
#     temp_file = await save_audio_file(audio_bytes)
    
#     try:
#         # Transcribe with OpenAI
#         with open(temp_file, "rb") as audio_file:
#             translation = openai_client.audio.translations.create(
#                 model="whisper-1",
#                 file=audio_file
#             )
#         english_text = translation.text
        
#         # Reverse translate to Turkish
#         turkish_text = await translate_with_google(english_text, source='en', target='tr')
        
#         logger.info(f"🎤 OpenAI: {turkish_text} → {english_text}")
        
#         return {
#             "method": "OpenAI API",
#             "turkish": turkish_text,
#             "english": english_text
#         }
        
#     except Exception as e:
#         logger.error(f"❌ OpenAI processing failed: {e}")
#         raise HTTPException(status_code=500, detail=f"OpenAI processing failed: {str(e)}")
#     finally:
#         cleanup_temp_file(temp_file)

# async def process_audio_local(audio_bytes: bytes) -> Dict[str, str]:
#     """Process audio using local Whisper model"""
#     if not whisper_model:
#         raise HTTPException(status_code=503, detail="Local Whisper model not available")
    
#     temp_file = await save_audio_file(audio_bytes)
    
#     try:
#         # Transcribe with local Whisper
#         result = whisper_model.transcribe(str(temp_file))
#         turkish_text = result["text"]
        
#         # Translate to English
#         english_text = await translate_with_google(turkish_text, source='tr', target='en')
        
#         logger.info(f"🎤 Local: {turkish_text} → {english_text}")
        
#         return {
#             "method": "Local LARGE",
#             "turkish": turkish_text,
#             "english": english_text
#         }
        
#     except Exception as e:
#         logger.error(f"❌ Local processing failed: {e}")
#         raise HTTPException(status_code=500, detail=f"Local processing failed: {str(e)}")
#     finally:
#         cleanup_temp_file(temp_file)

# # Yeni agent-powered endpoint
# async def process_audio_with_agent(audio_bytes: bytes) -> Dict[str, str]:
#     """Process audio using intelligent agent"""
#     if not translation_agent:
#         return await process_audio_openai(audio_bytes)  # Fallback
    
#     temp_file = await save_audio_file(audio_bytes)
    
#     try:
#         # Agent makes intelligent decisions
#         agent_result = await translation_agent.process_audio_intelligently(
#             str(temp_file), audio_bytes
#         )
        
#         # Process based on agent decision
#         if agent_result["processing_method"] == "openai":
#             result = await process_audio_openai(audio_bytes)
#         else:
#             result = await process_audio_local(audio_bytes)
        
#         # Add agent insights
#         result["agent_analysis"] = agent_result["agent_decision"]
#         result["audio_quality"] = agent_result["audio_analysis"]
#         result["method"] = f"Agent-Selected {result['method']}"
        
#         return result
        
#     except Exception as e:
#         logger.error(f"❌ Agent processing failed: {e}")
#         # Fallback to normal processing
#         return await process_audio_openai(audio_bytes)
#     finally:
#         cleanup_temp_file(temp_file)

# # WebSocket connection manager
# class ConnectionManager:
#     def __init__(self):
#         self.active_connections: Dict[str, WebSocket] = {}
#         self.heartbeat_tasks: Dict[str, asyncio.Task] = {}
    
#     async def connect(self, websocket: WebSocket, connection_id: str):
#         """Accept WebSocket connection"""
#         await websocket.accept()
#         self.active_connections[connection_id] = websocket
#         logger.info(f"✅ WebSocket connected: {connection_id}")
        
#         # Start heartbeat task
#         self.heartbeat_tasks[connection_id] = asyncio.create_task(
#             self.heartbeat_loop(websocket, connection_id)
#         )
    
#     def disconnect(self, connection_id: str):
#         """Remove WebSocket connection"""
#         if connection_id in self.active_connections:
#             del self.active_connections[connection_id]
        
#         # Cancel heartbeat task
#         if connection_id in self.heartbeat_tasks:
#             self.heartbeat_tasks[connection_id].cancel()
#             del self.heartbeat_tasks[connection_id]
        
#         logger.info(f"❌ WebSocket disconnected: {connection_id}")
    
#     async def send_message(self, connection_id: str, message: dict):
#         """Send message to specific WebSocket"""
#         if connection_id in self.active_connections:
#             websocket = self.active_connections[connection_id]
#             try:
#                 await websocket.send_text(json.dumps(message))
#             except Exception as e:
#                 logger.error(f"Failed to send message to {connection_id}: {e}")
#                 self.disconnect(connection_id)
    
#     async def heartbeat_loop(self, websocket: WebSocket, connection_id: str):
#         """Send periodic heartbeat to maintain connection"""
#         try:
#             while True:
#                 await asyncio.sleep(Config.HEARTBEAT_INTERVAL)
#                 if connection_id in self.active_connections:
#                     await websocket.send_text(json.dumps({"type": "ping"}))
#                     logger.debug(f"💓 Heartbeat sent to {connection_id}")
#                 else:
#                     break
#         except asyncio.CancelledError:
#             logger.debug(f"Heartbeat task cancelled for {connection_id}")
#         except Exception as e:
#             logger.error(f"Heartbeat error for {connection_id}: {e}")
#             self.disconnect(connection_id)

# manager = ConnectionManager()

# # API Routes
# @app.get("/")
# async def root():
#     """Health check endpoint"""
#     return {
#         "message": "Professional Voice Translator API",
#         "status": "running",
#         "version": "1.0.0",
#         "timestamp": datetime.now().isoformat(),
#         "services": {
#             "openai": openai_client is not None,
#             "whisper_local": whisper_model is not None
#         }
#     }

# @app.get("/health")
# async def health_check():
#     """Detailed health check"""
#     return {
#         "status": "healthy",
#         "timestamp": datetime.now().isoformat(),
#         "active_connections": len(manager.active_connections),
#         "services": {
#             "openai_api": openai_client is not None,
#             "whisper_local": whisper_model is not None
#         }
#     }

# # WebSocket endpoints
# @app.websocket("/ws/translate-api")
# async def websocket_translate_api(websocket: WebSocket):
#     """Real-time WebSocket endpoint using OpenAI API"""
#     connection_id = f"api_{uuid.uuid4().hex[:8]}"
    
#     await manager.connect(websocket, connection_id)
    
#     try:
#         while True:
#             data = await websocket.receive_text()
            
#             try:
#                 message = json.loads(data)
                
#                 # Handle heartbeat response
#                 if message.get("type") == "ping":
#                     await websocket.send_text(json.dumps({"type": "pong"}))
#                     continue
                
#                 # Handle audio data
#                 if message.get("type") == "audio" and "audio" in message:
#                     # Decode base64 audio
#                     audio_bytes = base64.b64decode(message["audio"])
                    
#                     # Validate file size
#                     if len(audio_bytes) > Config.MAX_FILE_SIZE:
#                         await manager.send_message(connection_id, {
#                             "error": "File too large",
#                             "max_size_mb": Config.MAX_FILE_SIZE // (1024 * 1024)
#                         })
#                         continue
                    
#                     # Process audio
#                     result = await process_audio_with_agent(audio_bytes)
#                     result["timestamp"] = message.get("timestamp", "")
#                     result["connection_id"] = connection_id
                    
#                     await manager.send_message(connection_id, result)
                
#             except json.JSONDecodeError:
#                 await manager.send_message(connection_id, {"error": "Invalid JSON format"})
#             except Exception as e:
#                 logger.error(f"Processing error for {connection_id}: {e}")
#                 await manager.send_message(connection_id, {"error": str(e)})
    
#     except WebSocketDisconnect:
#         logger.info(f"WebSocket client disconnected: {connection_id}")
#     except Exception as e:
#         logger.error(f"WebSocket error for {connection_id}: {e}")
#     finally:
#         manager.disconnect(connection_id)

# @app.websocket("/ws/translate-local")
# async def websocket_translate_local(websocket: WebSocket):
#     """Real-time WebSocket endpoint using local Whisper model"""
#     connection_id = f"local_{uuid.uuid4().hex[:8]}"
    
#     await manager.connect(websocket, connection_id)
    
#     try:
#         while True:
#             data = await websocket.receive_text()
            
#             try:
#                 message = json.loads(data)
                
#                 # Handle heartbeat response
#                 if message.get("type") == "ping":
#                     await websocket.send_text(json.dumps({"type": "pong"}))
#                     continue
                
#                 # Handle audio data
#                 if message.get("type") == "audio" and "audio" in message:
#                     # Decode base64 audio
#                     audio_bytes = base64.b64decode(message["audio"])
                    
#                     # Validate file size
#                     if len(audio_bytes) > Config.MAX_FILE_SIZE:
#                         await manager.send_message(connection_id, {
#                             "error": "File too large",
#                             "max_size_mb": Config.MAX_FILE_SIZE // (1024 * 1024)
#                         })
#                         continue
                    
#                     # Process audio
#                     result = await process_audio_local(audio_bytes)
#                     result["timestamp"] = message.get("timestamp", "")
#                     result["connection_id"] = connection_id
                    
#                     await manager.send_message(connection_id, result)
                
#             except json.JSONDecodeError:
#                 await manager.send_message(connection_id, {"error": "Invalid JSON format"})
#             except Exception as e:
#                 logger.error(f"Processing error for {connection_id}: {e}")
#                 await manager.send_message(connection_id, {"error": str(e)})

#     except WebSocketDisconnect:
#         logger.info(f"WebSocket client disconnected: {connection_id}")
#     except Exception as e:
#         logger.error(f"WebSocket error for {connection_id}: {e}")
#     finally:
#         manager.disconnect(connection_id)

# # HTTP endpoints for testing
# @app.post("/translate-audio-api")
# async def translate_audio_api(file: UploadFile = File(...)):
#     """HTTP endpoint for OpenAI API translation"""
#     if not openai_client:
#         raise HTTPException(status_code=503, detail="OpenAI API not available")
    
#     try:
#         # Validate file size
#         file_size = 0
#         audio_bytes = b""
        
#         async for chunk in file.stream():
#             file_size += len(chunk)
#             if file_size > Config.MAX_FILE_SIZE:
#                 raise HTTPException(status_code=413, detail="File too large")
#             audio_bytes += chunk
        
#         result = await process_audio_openai(audio_bytes)
#         return result
        
#     except HTTPException:
#         raise
#     except Exception as e:
#         logger.error(f"HTTP API processing error: {e}")
#         raise HTTPException(status_code=500, detail=str(e))

# @app.post("/translate-audio-local")
# async def translate_audio_local(file: UploadFile = File(...)):
#     """HTTP endpoint for local Whisper translation"""
#     if not whisper_model:
#         raise HTTPException(status_code=503, detail="Local Whisper model not available")
    
#     try:
#         # Validate file size
#         file_size = 0
#         audio_bytes = b""
        
#         async for chunk in file.stream():
#             file_size += len(chunk)
#             if file_size > Config.MAX_FILE_SIZE:
#                 raise HTTPException(status_code=413, detail="File too large")
#             audio_bytes += chunk
        
#         result = await process_audio_local(audio_bytes)
#         return result
        
#     except HTTPException:
#         raise
#     except Exception as e:
#         logger.error(f"HTTP Local processing error: {e}")
#         raise HTTPException(status_code=500, detail=str(e))

# # Error handlers
# @app.exception_handler(404)
# async def not_found_handler(request, exc):
#     return JSONResponse(
#         status_code=404,
#         content={"error": "Endpoint not found", "detail": "The requested endpoint does not exist"}
#     )

# @app.exception_handler(500)
# async def internal_error_handler(request, exc):
#     logger.error(f"Internal server error: {exc}")
#     return JSONResponse(
#         status_code=500,
#         content={"error": "Internal server error", "detail": "An unexpected error occurred"}
#     )

# # Main execution
# if __name__ == "__main__":
#     uvicorn.run(
#         "main:app",
#         host="0.0.0.0",
#         port=8000,
#         reload=True,
#         log_level="info",
#         access_log=True
#     )