"""
Otto Poker OCR Server
FastAPI Server für Kartenerkennung mit OpenCV
"""

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import cv2
import numpy as np
import base64
from PIL import Image
import io
import json

app = FastAPI(title="Otto Poker OCR Server")

# CORS erlauben
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Kartendefinitionen
RANKS = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2']
SUITS = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS']
SUIT_SYMBOLS = {'SPADES': '♠', 'HEARTS': '♥', 'DIAMONDS': '♦', 'CLUBS': '♣'}

def detect_cards_from_image(image_bytes: bytes) -> list:
    """Erkennt Pokerkarten im Bild"""
    try:
        # Bild decode
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            return []
        
        # Bild griskalieren für bessere Erkennung
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Threshold für Weiß und Rot
        _, binary = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY)
        
        # Konturen finden (mögliche Karten)
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        cards = []
        
        for cnt in contours:
            area = cv2.contourArea(cnt)
            if area < 5000:  # Zu klein
                continue
            if area > 100000:  # Zu groß (wahrscheinlich keine Karte)
                continue
                
            x, y, w, h = cv2.boundingRect(cnt)
            aspect_ratio = w / float(h)
            
            # Nur Rechtecke die wie Karten aussehen
            if 0.5 < aspect_ratio < 0.8:
                # Kartenausschnitt
                card_img = img[y:y+h, x:x+w]
                
                # Farberkennung für Suit
                hsv = cv2.cvtColor(card_img, cv2.COLOR_BGR2HSV)
                
                # Rot (Herz/Karo)
                red_lower = np.array([0, 100, 100])
                red_upper = np.array([10, 255, 255])
                red_mask = cv2.inRange(hsv, red_lower, red_upper)
                
                # Schwarz (Pik/Kreuz)
                black_lower = np.array([0, 0, 0])
                black_upper = np.array([180, 255, 50])
                black_mask = cv2.inRange(hsv, black_lower, black_upper)
                
                # Suit bestimmen
                red_pixels = cv2.countNonZero(red_mask)
                black_pixels = cv2.countNonZero(black_mask)
                
                if red_pixels > black_pixels:
                    #Wahrscheinlch Herz oder Karo
                    suit = 'HEARTS' if np.mean(hsv[:,:,0]) < 10 else 'DIAMONDS'
                else:
                    suit = 'CLUBS'
                
                # Vereinfachte Rang-Erkennung (kann mit ML verbessert werden)
                # Hier nutzen wir OCR-artige Flächenerkennung
                text_area = card_img[0:int(h*0.3), 0:int(w*0.4)]
                text_gray = cv2.cvtColor(text_area, cv2.COLOR_BGR2GRAY)
                
                # Vereinfacht: Wir geben die Position zurück für weitere Analyse
                # In einer echten Implementierung würde man ein ML-Modell nutzen
                
                cards.append({
                    'rank': 'Unknown',
                    'suit': suit,
                    'position': {'x': int(x), 'y': int(y)}
                })
        
        return cards
        
    except Exception as e:
        print(f"Error: {e}")
        return []

def simple_card_detection(image_bytes: bytes) -> list:
    """Einfache Kartenerkennung basierend auf Farben und Konturen"""
    try:
        # Bild decode
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            return []
        
        # Resolution runterskalieren für schnellere Verarbeitung
        scale = 0.5
        resized = cv2.resize(img, None, fx=scale, fy=scale)
        gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
        
        # Blur für bessere Konturen
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # Kanten erkennen
        edges = cv2.Canny(blurred, 50, 150)
        
        # Konturen finden
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        cards = []
        
        for cnt in contours:
            area = cv2.contourArea(cnt)
            
            # Kartengroße Bereich
            if 3000 < area < 30000:
                peri = cv2.arcLength(cnt, True)
                approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
                
                # Wenn es ein Rechteck ist (4 Ecken)
                if len(approx) == 4:
                    x, y, w, h = cv2.boundingRect(cnt)
                    aspect = w / float(h)
                    
                    # Nur Karten-aspect Ratio
                    if 0.5 < aspect < 0.9:
                        # Farbe im Kartenzentrum analysieren
                        center_region = resized[y+int(h*0.3):y+int(h*0.7), x+int(w*0.3):x+int(w*0.7)]
                        avg_color = np.mean(center_region, axis=(0,1))
                        
                        # Rot oder Schwarz?
                        is_red = avg_color[2] > avg_color[0] + 20
                        
                        suit = 'HEARTS' if is_red else 'SPADES'
                        
                        # Vereinfacht: Wir geben Unknown zurück, später mit ML verbessern
                        cards.append({
                            'rank': 'Unknown',
                            'suit': suit,
                            'confidence': 0.7
                        })
        
        return cards
        
    except Exception as e:
        print(f"Error in simple_card_detection: {e}")
        return []

@app.get("/")
def root():
    return {"message": "Otto Poker OCR Server", "status": "running"}

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.post("/detect")
async def detect_cards(file: UploadFile = File(...)):
    """Erkennt Karten im hochgeladenen Bild"""
    try:
        # Bild lesen
        image_bytes = await file.read()
        
        # Kartenerkennung
        cards = simple_card_detection(image_bytes)
        
        return {
            "success": True,
            "cards": cards,
            "count": len(cards)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/detect/base64")
async def detect_cards_base64(data: dict):
    """Erkennt Karten aus Base64 Bild"""
    try:
        # Base64 decode
        image_data = data.get("image", "")
        if not image_data:
            raise HTTPException(status_code=400, detail="No image provided")
        
        # Base64 zu Bild
        image_bytes = base64.b64decode(image_data)
        
        # Kartenerkennung
        cards = simple_card_detection(image_bytes)
        
        return {
            "success": True,
            "cards": cards,
            "count": len(cards)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    print("Starte Otto Poker OCR Server auf http://0.0.0.0:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)
