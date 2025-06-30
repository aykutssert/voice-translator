# agent.py - Yeni dosya oluştur
from langchain.agents import Tool, AgentExecutor, create_openai_tools_agent
from langchain_openai import ChatOpenAI
from langchain.prompts import ChatPromptTemplate
import librosa
import numpy as np
from typing import Dict, Any
import logging

logger = logging.getLogger(__name__)

class AudioQualityTool:
    """Audio quality analysis tool"""
    
    def analyze_audio_quality(self, audio_path: str) -> Dict[str, Any]:
        try:
            # Load audio file
            y, sr = librosa.load(audio_path)
            
            # Calculate metrics
            rms_energy = librosa.feature.rms(y=y)[0]
            spectral_centroids = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
            zero_crossing_rate = librosa.feature.zero_crossing_rate(y)[0]
            
            # Quality metrics
            avg_energy = np.mean(rms_energy)
            noise_level = np.std(rms_energy)
            clarity_score = np.mean(spectral_centroids)
            
            # Determine quality score (0-100)
            quality_score = min(100, int((avg_energy * 1000 + clarity_score/100) * 50))
            
            return {
                "quality_score": quality_score,
                "noise_level": float(noise_level),
                "clarity": float(clarity_score),
                "duration": len(y) / sr,
                "sample_rate": sr,
                "recommendation": self._get_recommendation(quality_score, noise_level)
            }
            
        except Exception as e:
            logger.error(f"Audio analysis failed: {e}")
            return {"quality_score": 0, "error": str(e)}
    
    def _get_recommendation(self, quality: int, noise: float) -> str:
        if quality < 30:
            return "ENHANCE_AUDIO"
        elif noise > 0.1:
            return "REDUCE_NOISE"
        elif quality > 80:
            return "PROCEED_DIRECT"
        else:
            return "STANDARD_PROCESSING"

class TranslationAgent:
    """Smart translation agent with quality control"""
    
    def __init__(self, openai_api_key: str):
        self.llm = ChatOpenAI(
            model="gpt-4",
            api_key=openai_api_key,
            temperature=0.3
        )
        
        self.audio_tool = AudioQualityTool()
        
        # Define tools
        self.tools = [
            Tool(
                name="analyze_audio_quality",
                description="Analyze audio quality, noise level, and recommend processing method",
                func=self._analyze_audio_wrapper
            ),
            Tool(
                name="evaluate_translation",
                description="Evaluate translation quality and decide if re-translation needed",
                func=self._evaluate_translation
            ),
            Tool(
                name="select_processing_method",
                description="Select best processing method based on audio characteristics",
                func=self._select_method
            )
        ]
        
        # Create agent
        self.agent = self._create_agent()
    
    def _create_agent(self):
        prompt = ChatPromptTemplate.from_messages([
            ("system", """You are an expert audio translation agent. Your job is to:
            1. Analyze incoming audio quality
            2. Select the best processing method
            3. Ensure translation quality
            4. Make recommendations for improvement
            
            Always respond with structured decisions and confidence scores."""),
            ("user", "{input}"),
            ("assistant", "{agent_scratchpad}")
        ])
        
        agent = create_openai_tools_agent(self.llm, self.tools, prompt)
        return AgentExecutor(agent=agent, tools=self.tools, verbose=True)
    
    def _analyze_audio_wrapper(self, audio_path: str) -> str:
        result = self.audio_tool.analyze_audio_quality(audio_path)
        return f"Audio Analysis: {result}"
    
    def _evaluate_translation(self, translation_data: str) -> str:
        # Parse translation data and evaluate
        try:
            data = eval(translation_data)  # In production, use json.loads
            
            source_text = data.get('turkish', '')
            target_text = data.get('english', '')
            
            # Simple evaluation metrics
            length_ratio = len(target_text) / max(len(source_text), 1)
            
            if length_ratio < 0.3 or length_ratio > 3.0:
                confidence = 30
                recommendation = "RE_TRANSLATE"
            elif len(target_text.split()) < 2 and len(source_text.split()) > 5:
                confidence = 40
                recommendation = "RE_TRANSLATE"
            else:
                confidence = 85
                recommendation = "ACCEPT"
            
            return f"Translation Quality: confidence={confidence}%, recommendation={recommendation}"
            
        except Exception as e:
            return f"Evaluation Error: {str(e)}"
    
    def _select_method(self, audio_quality_data: str) -> str:
        try:
            # Extract quality data
            if "quality_score" in audio_quality_data:
                # Parse quality score
                lines = audio_quality_data.split('\n')
                for line in lines:
                    if 'quality_score' in line:
                        score = int(line.split(':')[1].strip().replace(',', ''))
                        break
                else:
                    score = 50
                
                if score > 80:
                    return "USE_OPENAI_API - High quality audio detected"
                elif score > 50:
                    return "USE_LOCAL_WHISPER - Standard quality, local processing sufficient"
                else:
                    return "ENHANCE_THEN_PROCESS - Low quality, enhancement needed"
            
            return "USE_LOCAL_WHISPER - Default fallback"
            
        except Exception as e:
            return f"Method Selection Error: {str(e)}"
    
    async def process_audio_intelligently(self, audio_path: str, audio_bytes: bytes) -> Dict[str, Any]:
        """Main agent processing function"""
        try:
            # Agent decision-making process
            result = self.agent.invoke({
                "input": f"""
                Analyze the audio file at: {audio_path}
                Make intelligent decisions about:
                1. Audio quality and processing needs
                2. Best translation method to use
                3. Quality assurance requirements
                
                Provide structured recommendations.
                """
            })
            
            # Extract agent recommendations
            agent_output = result.get('output', '')
            
            # Parse agent decision and route accordingly
            if "USE_OPENAI_API" in agent_output:
                processing_method = "openai"
            elif "USE_LOCAL_WHISPER" in agent_output:
                processing_method = "local"
            else:
                processing_method = "local"  # Default
            
            return {
                "agent_decision": agent_output,
                "processing_method": processing_method,
                "audio_analysis": self.audio_tool.analyze_audio_quality(audio_path)
            }
            
        except Exception as e:
            logger.error(f"Agent processing failed: {e}")
            return {
                "agent_decision": f"Error: {str(e)}",
                "processing_method": "local",  # Fallback
                "audio_analysis": {"error": str(e)}
            }