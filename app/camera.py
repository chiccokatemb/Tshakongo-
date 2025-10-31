import cv2
class Camera:
    def __init__(self, index=0): self.cap=cv2.VideoCapture(index)
    def read(self):
        ok,frame=self.cap.read()
        return ok, frame
    def release(self):
        try: self.cap.release()
        except: pass
