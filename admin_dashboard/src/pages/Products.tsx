import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ShoppingBag, Plus, Edit2, Trash2, Loader2, DollarSign, Clock, Infinity, Zap } from 'lucide-react';

interface Product {
  id: string;
  product_code: string;
  title: string;
  description: string;
  price: number;
  product_type: 'subscription' | 'lifetime' | 'consumable';
  duration_days: number | null;
  is_active: boolean;
  created_at: string;
}

export default function Products() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  // Form State
  const [productCode, setProductCode] = useState('');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [price, setPrice] = useState(0);
  const [productType, setProductType] = useState<'subscription' | 'lifetime' | 'consumable'>('subscription');
  const [durationDays, setDurationDays] = useState<number | ''>('');
  const [isActive, setIsActive] = useState(true);

  useEffect(() => {
    fetchProducts();

    const channel = supabase
      .channel('products_changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'store_products' },
        () => {
          fetchProducts();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const fetchProducts = async () => {
    try {
      const { data, error } = await supabase
        .from('store_products')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setProducts(data || []);
    } catch (error) {
      console.error('Error fetching products:', error);
    } finally {
      setLoading(false);
    }
  };

  const resetForm = () => {
    setProductCode('');
    setTitle('');
    setDescription('');
    setPrice(0);
    setProductType('subscription');
    setDurationDays(30);
    setIsActive(true);
    setEditingId(null);
  };

  const openNewModal = () => {
    resetForm();
    setIsModalOpen(true);
  };

  const openEditModal = (product: Product) => {
    setProductCode(product.product_code);
    setTitle(product.title);
    setDescription(product.description || '');
    setPrice(product.price);
    setProductType(product.product_type);
    setDurationDays(product.duration_days || '');
    setIsActive(product.is_active);
    setEditingId(product.id);
    setIsModalOpen(true);
  };

  const handleSave = async () => {
    if (!productCode.trim() || !title.trim() || price < 0) {
      alert('Tüm zorunlu alanları (Kod, Başlık, Fiyat) geçerli şekilde doldurun.');
      return;
    }
    
    if (productType === 'subscription' && (durationDays === '' || Number(durationDays) <= 0)) {
        alert('Abonelik türü ürünlerde geçerli bir gün süresi girilmelidir.');
        return;
    }

    setSaving(true);
    try {
      const payload = {
        product_code: productCode.trim(),
        title: title.trim(),
        description: description.trim() || null,
        price: Number(price),
        product_type: productType,
        duration_days: productType === 'subscription' ? Number(durationDays) : null,
        is_active: isActive
      };

      if (editingId) {
        const { error } = await supabase
          .from('store_products')
          .update(payload)
          .eq('id', editingId);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('store_products')
          .insert([payload]);
        if (error) throw error;
      }
      
      setIsModalOpen(false);
      resetForm();
    } catch (error: any) {
      console.error('Error saving product:', error);
      alert('Kaydedilirken hata oluştu: ' + error.message);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!window.confirm('Bu ürünü silmek istediğinize emin misiniz? (Bağlı sahiplikler de etkilenebilir)')) return;
    
    try {
      const { error } = await supabase
        .from('store_products')
        .delete()
        .eq('id', id);
        
      if (error) throw error;
    } catch (error: any) {
      console.error('Error deleting product:', error);
      alert('Silinirken hata oluştu: ' + error.message);
    }
  };

  const toggleActiveStatus = async (id: string, currentStatus: boolean) => {
    try {
      const { error } = await supabase
        .from('store_products')
        .update({ is_active: !currentStatus })
        .eq('id', id);
        
      if (error) throw error;
    } catch (error: any) {
      console.error('Error toggling status:', error);
      alert('Durum güncellenirken hata oluştu: ' + error.message);
    }
  };

  const getTypeIcon = (type: string) => {
    switch(type) {
      case 'subscription': return <Clock className="w-5 h-5 text-indigo-500" />;
      case 'lifetime': return <Infinity className="w-5 h-5 text-emerald-500" />;
      case 'consumable': return <Zap className="w-5 h-5 text-orange-500" />;
      default: return <ShoppingBag className="w-5 h-5 text-blue-500" />;
    }
  };

  const getTypeLabel = (type: string) => {
    switch(type) {
      case 'subscription': return 'Abonelik';
      case 'lifetime': return 'Kalıcı Eşya';
      case 'consumable': return 'Tek Kullanımlık';
      default: return type;
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64 text-muted-foreground">
        <Loader2 className="w-8 h-8 animate-spin" />
        <span className="ml-2">Ürünler yükleniyor...</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">K-Coin Mağazası</h1>
          <p className="text-muted-foreground mt-1">
            Satıştaki uygulama içi ürünleri, paketleri ve fiyatlandırmaları yönetin.
          </p>
        </div>
        
        <button
          onClick={openNewModal}
          className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 transition-colors font-medium shadow-sm"
        >
          <Plus className="w-4 h-4" />
          Yeni Ürün Ekle
        </button>
      </div>

      <div className="grid gap-4 mt-6">
        {products.length === 0 ? (
          <div className="text-center py-12 border border-border rounded-xl bg-card">
            <ShoppingBag className="w-12 h-12 text-muted-foreground/50 mx-auto mb-3" />
            <h3 className="text-lg font-medium text-card-foreground">Henüz ürün yok</h3>
            <p className="text-muted-foreground mt-1 text-sm">Sağ üstteki butonu kullanarak mağazaya ilk ürününüzü ekleyin.</p>
          </div>
        ) : (
          products.map((product) => (
            <div 
              key={product.id} 
              className={`p-5 rounded-xl border transition-all ${
                product.is_active ? 'border-primary/20 bg-card shadow-sm' : 'border-border bg-muted/30 opacity-75'
              }`}
            >
              <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
                <div className="flex items-start gap-4 flex-1">
                  <div className={`p-3 rounded-xl flex-shrink-0 ${
                    product.product_type === 'subscription' ? 'bg-indigo-500/10' :
                    product.product_type === 'lifetime' ? 'bg-emerald-500/10' :
                    'bg-orange-500/10'
                  }`}>
                    {getTypeIcon(product.product_type)}
                  </div>
                  <div>
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-semibold text-lg text-card-foreground line-clamp-1">{product.title}</h3>
                      <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-secondary text-secondary-foreground border border-border/50">
                        {getTypeLabel(product.product_type)}
                      </span>
                      {product.duration_days && (
                        <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-500 border border-indigo-500/20">
                           {product.duration_days} Gün
                        </span>
                      )}
                      {product.is_active ? (
                        <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-500 border border-emerald-500/20">
                          SATIŞTA
                        </span>
                      ) : (
                        <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-muted text-muted-foreground border border-border">
                          PASİF
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-muted-foreground/90 whitespace-pre-wrap">{product.description}</p>
                    
                    <div className="flex items-center gap-4 mt-3 text-sm font-bold text-yellow-500">
                       <DollarSign className="w-4 h-4 mr-1" /> {product.price.toLocaleString()} K-Coin
                    </div>
                    <div className="mt-1 text-xs text-muted-foreground">
                       Kod: <code className="bg-muted px-1 py-0.5 rounded text-[10px]">{product.product_code}</code>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-2 sm:ml-4 w-full sm:w-auto mt-4 sm:mt-0 pt-4 sm:pt-0 border-t sm:border-none border-border">
                  <button
                    onClick={() => toggleActiveStatus(product.id, product.is_active)}
                    className={`flex-1 sm:flex-none px-3 py-1.5 rounded-md text-sm font-medium transition-colors border ${
                      product.is_active 
                        ? 'border-yellow-500/20 bg-yellow-500/10 text-yellow-600 hover:bg-yellow-500/20' 
                        : 'border-emerald-500/20 bg-emerald-500/10 text-emerald-600 hover:bg-emerald-500/20'
                    }`}
                  >
                    {product.is_active ? 'Satıştan Kaldır' : 'Satışa Aç'}
                  </button>
                  <button
                    onClick={() => openEditModal(product)}
                    className="p-2 border border-border rounded-md hover:bg-muted text-muted-foreground transition-colors"
                    title="Düzenle"
                  >
                    <Edit2 className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(product.id)}
                    className="p-2 border border-destructive/20 rounded-md hover:bg-destructive/10 text-destructive transition-colors"
                    title="Sil"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Create/Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-card w-full max-w-lg rounded-xl shadow-lg border border-border overflow-hidden flex flex-col max-h-[90vh]">
            <div className="px-6 py-4 border-b border-border bg-muted/30 shrink-0">
              <h3 className="text-lg font-bold text-card-foreground">
                {editingId ? 'Ürünü Düzenle' : 'Yeni Ürün Ekle'}
              </h3>
            </div>
            
            <div className="p-6 space-y-4 overflow-y-auto">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-1.5 text-card-foreground">Ürün Kodu <span className="text-destructive">*</span></label>
                  <input
                    type="text"
                    value={productCode}
                    onChange={(e) => setProductCode(e.target.value.toLowerCase().replace(/\s+/g, '_'))}
                    disabled={!!editingId} // Usually code shouldn't change after creation or it breaks client logic
                    placeholder="örn: ai_premium_1m"
                    className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-1.5 text-card-foreground">Fiyat (K-Coin) <span className="text-destructive">*</span></label>
                  <input
                    type="number"
                    value={price}
                    onChange={(e) => setPrice(Number(e.target.value))}
                    min="0"
                    className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium mb-1.5 text-card-foreground">Görünür Başlık <span className="text-destructive">*</span></label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Örn: Aylık VIP AI Paketi"
                  className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-1.5 text-card-foreground">Açıklama</label>
                <textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Ürünün avantajları ve özellikleri..."
                  rows={3}
                  className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary resize-y"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-1.5 text-card-foreground">Ürün Tipi</label>
                  <select
                    value={productType}
                    onChange={(e) => setProductType(e.target.value as any)}
                    className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                  >
                    <option value="subscription">Abonelik (Süreli)</option>
                    <option value="lifetime">Kalıcı Kilit Açma</option>
                    <option value="consumable">Tek Tüketimlik (Kullan-At)</option>
                  </select>
                </div>
                
                {productType === 'subscription' && (
                  <div>
                    <label className="block text-sm font-medium mb-1.5 text-card-foreground">Süre (Gün) <span className="text-destructive">*</span></label>
                    <input
                      type="number"
                      value={durationDays}
                      onChange={(e) => setDurationDays(Number(e.target.value))}
                      min="1"
                      className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                    />
                  </div>
                )}
              </div>

              <div className="pt-2">
                <label className="block text-sm font-medium mb-1.5 text-card-foreground">Durum</label>
                <div className="flex items-center h-[38px]">
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input 
                      type="checkbox" 
                      className="sr-only peer" 
                      checked={isActive}
                      onChange={(e) => setIsActive(e.target.checked)}
                    />
                    <div className="w-11 h-6 bg-muted peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-primary rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
                    <span className="ml-3 text-sm font-medium text-muted-foreground">
                      {isActive ? 'Aktif (Satışta)' : 'Pasif (Gizli)'}
                    </span>
                  </label>
                </div>
              </div>
            </div>
            
            <div className="px-6 py-4 border-t border-border bg-muted/30 flex items-center justify-end gap-3 shrink-0">
              <button
                onClick={() => setIsModalOpen(false)}
                className="px-4 py-2 text-sm rounded-md hover:bg-muted font-medium transition-colors"
                disabled={saving}
              >
                İptal
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="px-4 py-2 text-sm rounded-md bg-primary text-primary-foreground font-medium hover:bg-primary/90 transition-colors flex items-center gap-2"
              >
                {saving && <Loader2 className="w-4 h-4 animate-spin" />}
                {saving ? 'Kaydediliyor...' : 'Kaydet'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
