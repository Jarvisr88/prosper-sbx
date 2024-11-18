import { Request, Response, NextFunction } from 'express';
import jwt, { JsonWebTokenError, JwtPayload } from 'jsonwebtoken';

// Extend Express Request type to include user
declare module 'express' {
  interface Request {
    user?: JwtPayload;
  }
}

export const authMiddleware = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    
    if (!token) {
      return res.status(401).json({ 
        success: false, 
        error: 'No token provided' 
      });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as JwtPayload;
    req.user = decoded;
    
    next();
  } catch (err) {
    if (err instanceof JsonWebTokenError) {
      return res.status(401).json({ 
        success: false, 
        error: err.message 
      });
    }
    
    return res.status(401).json({ 
      success: false, 
      error: 'Invalid token' 
    });
  }
}; 