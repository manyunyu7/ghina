import {
  Utensils, ShoppingCart, ShoppingBag, Car, Bus, Fuel, Home, Zap, Wifi,
  Phone, HeartPulse, Pill, GraduationCap, BookOpen, Gamepad2, Film, Music,
  Plane, Gift, Coffee, Dumbbell, Shirt, Baby, Dog, Briefcase, Landmark,
  PiggyBank, TrendingUp, Wallet, Banknote, CreditCard, CircleDollarSign,
  Receipt, Circle, Tv, Cloud, Newspaper, Sparkles, type LucideIcon,
} from "lucide-react";

const ICON_MAP: Record<string, LucideIcon> = {
  "utensils": Utensils, "shopping-cart": ShoppingCart, "shopping-bag": ShoppingBag,
  "car": Car, "bus": Bus, "fuel": Fuel, "home": Home, "zap": Zap, "wifi": Wifi,
  "phone": Phone, "heart-pulse": HeartPulse, "pill": Pill, "graduation-cap": GraduationCap,
  "book-open": BookOpen, "gamepad-2": Gamepad2, "film": Film, "music": Music,
  "plane": Plane, "gift": Gift, "coffee": Coffee, "dumbbell": Dumbbell, "shirt": Shirt,
  "baby": Baby, "dog": Dog, "briefcase": Briefcase, "landmark": Landmark,
  "piggy-bank": PiggyBank, "trending-up": TrendingUp, "wallet": Wallet,
  "banknote": Banknote, "credit-card": CreditCard, "circle-dollar-sign": CircleDollarSign,
  "receipt": Receipt, "circle": Circle, "tv": Tv, "cloud": Cloud,
  "newspaper": Newspaper, "sparkles": Sparkles,
};

export function CategoryIcon({
  name,
  className,
}: {
  name?: string | null;
  className?: string;
}) {
  const Cmp = (name && ICON_MAP[name]) || Circle;
  return <Cmp className={className} />;
}

export function getIconComponent(name?: string | null): LucideIcon {
  return (name && ICON_MAP[name]) || Circle;
}
