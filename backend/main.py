import urllib.parse
import os
import httpx
from dotenv import load_dotenv
from datetime import datetime, timedelta
from typing import Optional

import uvicorn
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from sqlalchemy import create_engine, Integer, String, Text, DateTime, text, select, func
from sqlalchemy.orm import sessionmaker, Session, DeclarativeBase, Mapped, mapped_column
from pgvector.sqlalchemy import Vector
from passlib.context import CryptContext
from sentence_transformers import SentenceTransformer

# --- Carrega Variáveis de Ambiente ---
load_dotenv()

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
GOOGLE_CX = os.getenv("GOOGLE_CX")
VIRUSTOTAL_API_KEY = os.getenv("VIRUSTOTAL_API_KEY")

# --- Configurações de Segurança ---
# Contexto para hashing de senhas (bcrypt)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# --- Carrega Modelo de Embeddings ---
# Modelo leve (L6-v2) ideal para CPU e resposta rápida
embedding_model = SentenceTransformer('all-MiniLM-L6-v2')

# --- Configuração do Banco de Dados ---
DB_USER = "postgres"
DB_PASSWORD_RAW = "@energy12#"
DB_HOST = "localhost"
DB_PORT = "5432"
DB_NAME = "mdxhq_global"

# Tratamento de segurança para senha do banco (evita erros com caracteres especiais)
DB_PASSWORD_ESCAPED = urllib.parse.quote_plus(DB_PASSWORD_RAW)

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD_ESCAPED}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Criação da Engine e Sessão
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base Declarativa Moderna (SQLAlchemy 2.0)
class Base(DeclarativeBase):
    pass

# --- Modelos (SQLAlchemy) ---

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    trial_ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

class GlobalScam(Base):
    __tablename__ = "global_scams"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # Suporte a vetores de 384 dimensões (pgvector)
    embedding = mapped_column(Vector(384))
    category: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    hits: Mapped[int] = mapped_column(Integer, default=0)

class DeviceTrial(Base):
    __tablename__ = "device_trials"

    device_id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    first_access_date: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

# Cria as tabelas no banco de dados se não existirem
Base.metadata.create_all(bind=engine)

# --- Migração Manual para adicionar coluna hits (se não existir) ---
try:
    with engine.connect() as conn:
        conn.execute(text("ALTER TABLE global_scams ADD COLUMN hits INTEGER DEFAULT 0"))
        conn.commit()
        print("Migração: Coluna 'hits' adicionada com sucesso.")
except Exception as e:
    # Se der erro, provavelmente a coluna já existe
    pass

# --- Schemas (Pydantic) ---

class UserCreate(BaseModel):
    email: EmailStr
    password: str

class AnalyzeRequest(BaseModel):
    text: str

class UrlScanRequest(BaseModel):
    url: str
    sms_text: Optional[str] = None

class PhoneScanRequest(BaseModel):
    phone: str
    sms_text: Optional[str] = None

class TrialRequest(BaseModel):
    device_id: str

class ReportThreatRequest(BaseModel):
    text: str
    sender: str
    category: str
    risk_score: float
    manual_confirmation: bool = False
    timestamp: Optional[str] = None

# --- Dependências ---

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Inicialização da App ---

app = FastAPI(title="MDXHQ Global Security API", version="1.0.0")

# --- Configuração CORS (Permite conexão do Flutter/Cloudflare) ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Em produção, substitua por domínios específicos
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Rotas ---

@app.get("/")
def home():
    return {"status": "MDXHQ Global Server Online", "version": "1.0.0"}

@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    try:
        # Correção SQL para SQLAlchemy 2.0
        db.execute(text("SELECT 1"))
        return {"database": "connected", "vector_extension": "active"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro de conexão: {str(e)}")

@app.post("/auth/register", status_code=status.HTTP_201_CREATED)
def register(user: UserCreate, db: Session = Depends(get_db)):
    # Verifica se usuário já existe
    stmt = select(User).where(User.email == user.email)
    existing_user = db.execute(stmt).scalar_one_or_none()
    
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # Hash da senha
    hashed_pw = pwd_context.hash(user.password)
    
    # Cria novo usuário
    new_user = User(
        email=user.email,
        hashed_password=hashed_pw,
        # Define um período de trial padrão (ex: 14 dias)
        trial_ends_at=datetime.utcnow() + timedelta(days=14)
    )
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    return {"id": new_user.id, "email": new_user.email, "message": "User created successfully"}

@app.post("/analyze")
def analyze(request: AnalyzeRequest):
    # Placeholder que retorna JSON conforme solicitado
    return {"status": "received", "message": "Pronto para processar vetores"}

@app.post("/analyze/global")
async def analyze_global(request: AnalyzeRequest, db: Session = Depends(get_db)):
    try:
        # 1. Gera embedding do texto recebido
        embedding = embedding_model.encode(request.text).tolist()
        
        # 2. Busca por similaridade no banco (pgvector cosine distance)
        # Operador <=> é cosine distance. Ordenamos pela distância menor (mais similar).
        stmt = select(GlobalScam).order_by(GlobalScam.embedding.cosine_distance(embedding)).limit(1)
        result = db.execute(stmt).scalar_one_or_none()
        
        if result:
            # Recalcula a distância para validar o threshold (pgvector retorna o objeto, não a distância direto no scalar)
            # Para pegar a distância, precisamos ajustar a query ou calcular manual se não vier.
            # Vamos ajustar a query para retornar (GlobalScam, distance)
            stmt_dist = select(GlobalScam, GlobalScam.embedding.cosine_distance(embedding).label("distance")) \
                        .order_by("distance") \
                        .limit(1)
            
            row = db.execute(stmt_dist).first()
            
            if row:
                scam, distance = row
                # Similaridade = 1 - distância
                similarity = 1 - distance
                
                print(f"🔍 Análise Global: Similaridade {similarity:.4f} com ID {scam.id}")
                
                # Threshold de 90% (Distância < 0.1)
                if distance < 0.1:
                    # Incrementa o contador de hits (golpes bloqueados)
                    scam.hits += 1
                    db.commit()
                    
                    return {
                        "status": "CONFIRMED_SCAM", 
                        "source": "MDXHQ Community",
                        "similarity": similarity,
                        "category": scam.category
                    }

        return {"status": "CLEAN", "message": "Nenhuma ameaça global similar encontrada."}
        
    except Exception as e:
        print(f"Erro na análise global: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/report/threat")
def report_threat(request: ReportThreatRequest, db: Session = Depends(get_db)):
    try:
        # 1. Verifica se já existe por conteúdo exato (evita duplicação trivial)
        stmt = select(GlobalScam).where(GlobalScam.content == request.text)
        existing = db.execute(stmt).scalar_one_or_none()
        
        if existing:
            # Se já existe, apenas incrementa hits
            existing.hits += 1
            # Atualiza categoria se a nova for mais específica
            if request.category != "Desconhecido" and (existing.category == "Desconhecido" or existing.category is None):
                existing.category = request.category
            
            db.commit()
            print(f"🔄 Ameaça já conhecida reportada. Hits incrementados para {existing.hits}.")
            return {"status": "UPDATED", "message": "Threat known, hits updated."}
        else:
            # 2. Nova ameaça: Gera embedding e salva
            print(f"🆕 Nova ameaça reportada: {request.text[:50]}...")
            embedding = embedding_model.encode(request.text).tolist()
            
            new_scam = GlobalScam(
                content=request.text,
                embedding=embedding,
                category=request.category,
                hits=1 
            )
            db.add(new_scam)
            db.commit()
            print("✅ Nova ameaça global salva com sucesso!")
            return {"status": "CREATED", "message": "New global threat registered."}
            
    except Exception as e:
        print(f"❌ Erro ao reportar ameaça: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/stats/summary")
def get_stats(db: Session = Depends(get_db)):
    try:
        # Total de vacinas (golpes únicos cadastrados)
        total_scams = db.execute(select(func.count(GlobalScam.id))).scalar() or 0
        
        # Total de bloqueios (soma dos hits)
        total_blocked = db.execute(select(func.sum(GlobalScam.hits))).scalar() or 0
        
        # Usuários ativos (total de usuários registrados)
        active_users = db.execute(select(func.count(User.id))).scalar() or 0
        
        return {
            "total_scams": total_scams,
            "total_blocked": total_blocked,
            "active_users": active_users
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/trial/status")
def check_trial(request: TrialRequest, db: Session = Depends(get_db)):
    try:
        device_id = request.device_id
        
        stmt = select(DeviceTrial).where(DeviceTrial.device_id == device_id)
        trial = db.execute(stmt).scalar_one_or_none()
        
        now = datetime.utcnow()
        trial_days = 7
        
        if not trial:
            # Primeiro acesso: cria registro
            new_trial = DeviceTrial(device_id=device_id)
            db.add(new_trial)
            db.commit()
            return {"is_valid": True, "days_remaining": trial_days, "status": "trial_started"}
        else:
            # Verifica expiração
            elapsed = now - trial.first_access_date
            remaining = trial_days - elapsed.days
            
            if remaining > 0:
                return {"is_valid": True, "days_remaining": remaining, "status": "active"}
            else:
                return {"is_valid": False, "days_remaining": 0, "status": "expired"}
                
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan/url")
async def scan_url(request: UrlScanRequest, db: Session = Depends(get_db)):
    # Fallback se a chave não estiver configurada ou falhar
    if not VIRUSTOTAL_API_KEY:
        print("⚠️ VirusTotal Key ausente. Usando apenas vacina global.")
        return {"malicious": False, "message": "API Key missing, rely on global vaccine"}
    
    url = request.url
    # 1. Enviar URL para scan (POST)
    scan_url_endpoint = "https://www.virustotal.com/api/v3/urls"
    headers = {
        "x-apikey": VIRUSTOTAL_API_KEY,
        "Content-Type": "application/x-www-form-urlencoded"
    }
    
    async with httpx.AsyncClient() as client:
        try:
            # Primeiro submete a URL
            response = await client.post(scan_url_endpoint, data={"url": url}, headers=headers)
            
            # O fluxo correto do VT é: POST url -> recebe ID -> GET analysis/ID
            import base64
            url_id = base64.urlsafe_b64encode(url.encode()).decode().strip("=")
            report_url = f"https://www.virustotal.com/api/v3/urls/{url_id}"
            
            report_response = await client.get(report_url, headers=headers)
            
            if report_response.status_code == 200:
                data = report_response.json()
                stats = data.get("data", {}).get("attributes", {}).get("last_analysis_stats", {})
                malicious = stats.get("malicious", 0)
                
                # --- AUTO-VACINA: Salvar no Banco se for malicioso ---
                if malicious > 0 and request.sms_text:
                    try:
                        # Gera embedding do texto do SMS
                        embedding = embedding_model.encode(request.sms_text).tolist()
                        
                        # Verifica se já existe (evita duplicatas exatas de conteúdo)
                        stmt = select(GlobalScam).where(GlobalScam.content == request.sms_text)
                        existing = db.execute(stmt).scalar_one_or_none()
                        
                        if not existing:
                            new_scam = GlobalScam(
                                content=request.sms_text,
                                embedding=embedding,
                                category="URL_MALICIOSA"
                            )
                            db.add(new_scam)
                            db.commit()
                            print(f"💉 VACINA: SMS malicioso salvo no banco global (URL Detected).")
                    except Exception as e:
                        print(f"Erro ao salvar vacina: {e}")

                return {"malicious": malicious > 0, "stats": stats}
            elif report_response.status_code == 404:
                return {"malicious": False, "message": "URL not found in VirusTotal database"}
            else:
                # Erro na API externa (403, 500, etc) -> Fallback seguro
                print(f"⚠️ Erro VirusTotal ({report_response.status_code}). Retornando falso negativo para não travar.")
                return {"malicious": False, "error": "External API Error"}
                
        except Exception as e:
            # Erro de conexão ou timeout -> Fallback seguro
            print(f"⚠️ Erro conexão VirusTotal: {e}")
            return {"malicious": False, "error": str(e)}

@app.post("/scan/phone")
async def scan_phone(request: PhoneScanRequest, db: Session = Depends(get_db)):
    # Fallback se a chave não estiver configurada
    if not GOOGLE_API_KEY or not GOOGLE_CX:
        print("⚠️ Google Keys ausentes. Usando apenas vacina global.")
        return {"complaints": 0, "message": "API Keys missing, rely on global vaccine"}
    
    bait = request.phone
    
    base_url = "https://www.googleapis.com/customsearch/v1"
    params = {
        "key": GOOGLE_API_KEY,
        "cx": GOOGLE_CX,
        "q": f"\"{bait}\" reclamação golpe",
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(base_url, params=params)
            if response.status_code == 200:
                data = response.json()
                search_info = data.get("searchInformation", {})
                total_results = int(search_info.get("totalResults", "0"))
                
                # --- AUTO-VACINA: Salvar no Banco se tiver muitas reclamações ---
                if total_results > 0 and request.sms_text:
                     try:
                        # Gera embedding do texto do SMS
                        embedding = embedding_model.encode(request.sms_text).tolist()
                        
                        stmt = select(GlobalScam).where(GlobalScam.content == request.sms_text)
                        existing = db.execute(stmt).scalar_one_or_none()
                        
                        if not existing:
                            new_scam = GlobalScam(
                                content=request.sms_text,
                                embedding=embedding,
                                category="TELEFONE_GOLPE"
                            )
                            db.add(new_scam)
                            db.commit()
                            print(f"💉 VACINA: SMS malicioso salvo no banco global (Phone Detected).")
                     except Exception as e:
                        print(f"Erro ao salvar vacina: {e}")

                return {"complaints": total_results}
            else:
                # Erro na API externa (403 Cota Excedida, etc) -> Fallback seguro
                print(f"⚠️ Erro Google API ({response.status_code}): {response.text}")
                return {"complaints": 0, "error": "External API Error"}
        except Exception as e:
            # Erro de conexão ou timeout -> Fallback seguro
            print(f"⚠️ Erro conexão Google: {e}")
            return {"complaints": 0, "error": str(e)}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
