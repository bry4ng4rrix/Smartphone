"use strict";
// Django Backend API Client with JWT Authentication
// Handles all API calls to Django backend with automatic token management
var __assign = (this && this.__assign) || function () {
    __assign = Object.assign || function(t) {
        for (var s, i = 1, n = arguments.length; i < n; i++) {
            s = arguments[i];
            for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
                t[p] = s[p];
        }
        return t;
    };
    return __assign.apply(this, arguments);
};
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
var __spreadArray = (this && this.__spreadArray) || function (to, from, pack) {
    if (pack || arguments.length === 2) for (var i = 0, l = from.length, ar; i < l; i++) {
        if (ar || !(i in from)) {
            if (!ar) ar = Array.prototype.slice.call(from, 0, i);
            ar[i] = from[i];
        }
    }
    return to.concat(ar || Array.prototype.slice.call(from));
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.djangoClient = void 0;
var API_BASE_URL = process.env.NEXT_PUBLIC_DJANGO_API_URL || 'http://localhost:8000/api';
var DjangoAPIClient = /** @class */ (function () {
    function DjangoAPIClient() {
        var _this = this;
        this.tokens = null;
        this.isRefreshing = false;
        this.refreshQueue = [];
        // ==================== Authentication Service ====================
        this.auth = {
            register: function (email, username, password, role, extraData) { return __awaiter(_this, void 0, void 0, function () {
                var backendRole;
                return __generator(this, function (_a) {
                    backendRole = role;
                    if (role === 'store_manager')
                        backendRole = 'magasin';
                    if (role === 'employee')
                        backendRole = 'employer';
                    return [2 /*return*/, this.post('/users/register/', __assign({ email: email, username: username, password: password, role: backendRole, full_name: (extraData === null || extraData === void 0 ? void 0 : extraData.full_name) || username }, extraData))];
                });
            }); },
            login: function (email, password) { return __awaiter(_this, void 0, void 0, function () {
                var response, user;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0: return [4 /*yield*/, this.post('/users/login/', {
                                email: email,
                                password: password,
                            })];
                        case 1:
                            response = _a.sent();
                            this.saveTokensToStorage({ access: response.access, refresh: response.refresh });
                            return [4 /*yield*/, this.auth.getCurrentUser()];
                        case 2:
                            user = _a.sent();
                            return [2 /*return*/, {
                                    access: response.access,
                                    refresh: response.refresh,
                                    user: user,
                                }];
                    }
                });
            }); },
            logout: function () { return __awaiter(_this, void 0, void 0, function () {
                var refreshToken, error_1;
                var _a;
                return __generator(this, function (_b) {
                    switch (_b.label) {
                        case 0:
                            refreshToken = ((_a = this.tokens) === null || _a === void 0 ? void 0 : _a.refresh) || (function () {
                                if (typeof window === 'undefined')
                                    return null;
                                try {
                                    var stored = localStorage.getItem('django_tokens');
                                    return stored ? JSON.parse(stored).refresh : null;
                                }
                                catch (_a) {
                                    return null;
                                }
                            })();
                            if (!refreshToken) return [3 /*break*/, 4];
                            _b.label = 1;
                        case 1:
                            _b.trys.push([1, 3, , 4]);
                            return [4 /*yield*/, fetch("".concat(API_BASE_URL, "/users/refresh/"), {
                                    method: 'POST',
                                    headers: { 'Content-Type': 'application/json' },
                                    body: JSON.stringify({ refresh: refreshToken }),
                                })];
                        case 2:
                            _b.sent();
                            return [3 /*break*/, 4];
                        case 3:
                            error_1 = _b.sent();
                            console.warn('[v0] Logout refresh request failed:', error_1);
                            return [3 /*break*/, 4];
                        case 4:
                            if (typeof window !== 'undefined') {
                                localStorage.clear();
                            }
                            this.tokens = null;
                            return [2 /*return*/];
                    }
                });
            }); },
            getCurrentUser: function () { return __awaiter(_this, void 0, void 0, function () {
                var response, mappedRole;
                var _a, _b;
                return __generator(this, function (_c) {
                    switch (_c.label) {
                        case 0: return [4 /*yield*/, this.get('/users/me/')];
                        case 1:
                            response = _c.sent();
                            mappedRole = 'employee';
                            if (response.role === 'admin')
                                mappedRole = 'admin';
                            else if (response.role === 'magasin')
                                mappedRole = 'store_manager';
                            else if (response.role === 'employer')
                                mappedRole = 'employee';
                            return [2 /*return*/, {
                                    id: response.id,
                                    email: response.email,
                                    username: response.username,
                                    full_name: response.full_name || '',
                                    first_name: ((_a = response.full_name) === null || _a === void 0 ? void 0 : _a.split(' ')[0]) || '',
                                    last_name: ((_b = response.full_name) === null || _b === void 0 ? void 0 : _b.split(' ').slice(1).join(' ')) || '',
                                    phone: response.phone,
                                    role: mappedRole,
                                    raw_role: response.role,
                                    is_approved: response.is_confirmed,
                                    is_confirmed: response.is_confirmed,
                                    company_name: response.company_name,
                                    shop_name: response.shop_name,
                                    magasin_id: response.magasin_id,
                                    position: response.position,
                                }];
                    }
                });
            }); },
            approveUser: function (userId) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.put("/users/approve/".concat(userId, "/"))];
                });
            }); },
            rejectUser: function (userId) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.post("/users/reject/".concat(userId, "/"))];
                });
            }); },
            getPendingUsers: function () { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get('/users/pending/')];
                });
            }); },
        };
        // ==================== Products Service ====================
        this.products = {
            list: function (filters) { return __awaiter(_this, void 0, void 0, function () {
                var params, query;
                return __generator(this, function (_a) {
                    params = new URLSearchParams();
                    if (filters === null || filters === void 0 ? void 0 : filters.store_id)
                        params.append('store_id', filters.store_id.toString());
                    if (filters === null || filters === void 0 ? void 0 : filters.category)
                        params.append('category', filters.category);
                    query = params.toString() ? "?".concat(params.toString()) : '';
                    return [2 /*return*/, this.get("/users/products/".concat(query))];
                });
            }); },
            getById: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get("/users/products/".concat(id, "/"))];
                });
            }); },
            create: function (data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.post('/users/products/', data)];
                });
            }); },
            update: function (id, data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.put("/users/products/".concat(id, "/"), data)];
                });
            }); },
            delete: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.delete("/users/products/".concat(id, "/"))];
                });
            }); },
            search: function (query) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get("/users/products/?search=".concat(encodeURIComponent(query)))];
                });
            }); },
        };
        // ==================== Sales Service ====================
        this.sales = {
            create: function (data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.post('/users/sales/', data)];
                });
            }); },
            list: function (filters) { return __awaiter(_this, void 0, void 0, function () {
                var params, query;
                return __generator(this, function (_a) {
                    params = new URLSearchParams();
                    if (filters === null || filters === void 0 ? void 0 : filters.store_id)
                        params.append('store_id', filters.store_id.toString());
                    if (filters === null || filters === void 0 ? void 0 : filters.date_range)
                        params.append('date_range', filters.date_range);
                    query = params.toString() ? "?".concat(params.toString()) : '';
                    return [2 /*return*/, this.get("/users/sales/".concat(query))];
                });
            }); },
            getById: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get("/users/sales/".concat(id, "/"))];
                });
            }); },
            update: function (id, data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.put("/users/sales/".concat(id, "/"), data)];
                });
            }); },
            delete: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.delete("/users/sales/".concat(id, "/"))];
                });
            }); },
            getByStore: function (storeId) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get("/users/sales/?store_id=".concat(storeId))];
                });
            }); },
            getRevenueSummary: function (storeId) { return __awaiter(_this, void 0, void 0, function () {
                var _a, totals, profit;
                return __generator(this, function (_b) {
                    switch (_b.label) {
                        case 0: return [4 /*yield*/, Promise.all([
                                this.get('/users/sales/totals/'),
                                this.get('/users/sales/profit/'),
                            ])];
                        case 1:
                            _a = _b.sent(), totals = _a[0], profit = _a[1];
                            return [2 /*return*/, __assign(__assign({}, totals), profit)];
                    }
                });
            }); },
        };
        // ==================== Movements Service ====================
        this.movements = {
            list: function (filters) { return __awaiter(_this, void 0, void 0, function () {
                var params, query;
                return __generator(this, function (_a) {
                    params = new URLSearchParams();
                    if (filters === null || filters === void 0 ? void 0 : filters.store_id)
                        params.append('store_id', filters.store_id.toString());
                    if (filters === null || filters === void 0 ? void 0 : filters.movement_type)
                        params.append('movement_type', filters.movement_type);
                    query = params.toString() ? "?".concat(params.toString()) : '';
                    return [2 /*return*/, this.get("/users/movements/".concat(query))];
                });
            }); },
            getById: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get("/users/movements/".concat(id, "/"))];
                });
            }); },
        };
        // ==================== Users Service ====================
        this.users = {
            list: function (role) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get('/users/magasins/users/')];
                });
            }); },
            getById: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get("/users/me/")];
                });
            }); },
            update: function (id, data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.put("/users/role/".concat(id, "/"), data)];
                });
            }); },
            delete: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.delete("/users/delete/".concat(id, "/"))];
                });
            }); },
            updateProfile: function (data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.patch('/users/me/', data)];
                });
            }); },
            getEmployeesByStore: function (storeId) { return __awaiter(_this, void 0, void 0, function () {
                var list, found;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0: return [4 /*yield*/, this.get('/users/magasins/users/')];
                        case 1:
                            list = _a.sent();
                            found = list.find(function (m) { return m.magasin_id === storeId; });
                            return [2 /*return*/, found ? found.employers : []];
                    }
                });
            }); },
        };
        // ==================== Dashboard Service ====================
        this.dashboard = {
            getStats: function (storeId) { return __awaiter(_this, void 0, void 0, function () {
                var res;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0: return [4 /*yield*/, this.get('/users/dashboard/')];
                        case 1:
                            res = _a.sent();
                            return [2 /*return*/, res.kpis];
                    }
                });
            }); },
            getTopProducts: function (storeId_1) {
                var args_1 = [];
                for (var _i = 1; _i < arguments.length; _i++) {
                    args_1[_i - 1] = arguments[_i];
                }
                return __awaiter(_this, __spreadArray([storeId_1], args_1, true), void 0, function (storeId, limit) {
                    var res;
                    var _a;
                    if (limit === void 0) { limit = 5; }
                    return __generator(this, function (_b) {
                        switch (_b.label) {
                            case 0: return [4 /*yield*/, this.get('/users/dashboard/')];
                            case 1:
                                res = _b.sent();
                                return [2 /*return*/, ((_a = res.lists) === null || _a === void 0 ? void 0 : _a.top_products) || []];
                        }
                    });
                });
            },
            getRevenueChart: function (storeId_1) {
                var args_1 = [];
                for (var _i = 1; _i < arguments.length; _i++) {
                    args_1[_i - 1] = arguments[_i];
                }
                return __awaiter(_this, __spreadArray([storeId_1], args_1, true), void 0, function (storeId, period) {
                    var res;
                    var _a;
                    if (period === void 0) { period = 'monthly'; }
                    return __generator(this, function (_b) {
                        switch (_b.label) {
                            case 0: return [4 /*yield*/, this.get('/users/dashboard/')];
                            case 1:
                                res = _b.sent();
                                return [2 /*return*/, ((_a = res.lists) === null || _a === void 0 ? void 0 : _a.recent_sales) || []];
                        }
                    });
                });
            },
            getSalesAnalytics: function (storeId) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get('/users/dashboard/')];
                });
            }); },
        };
        // ==================== Stores Service ====================
        this.stores = {
            list: function () { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get('/users/magasins/users/')];
                });
            }); },
            getProfitByMagasins: function () { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.get('/users/sales/profit-by-magasins/')];
                });
            }); },
            create: function (data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.post('/users/magasins/users/', data)];
                });
            }); },
            update: function (id, data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.put("/users/magasins/users/".concat(id, "/"), data)];
                });
            }); },
            delete: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, this.delete("/users/magasins/users/".concat(id, "/"))];
                });
            }); },
            getStoreByManager: function (managerId) { return __awaiter(_this, void 0, void 0, function () {
                var list;
                return __generator(this, function (_a) {
                    switch (_a.label) {
                        case 0: return [4 /*yield*/, this.list()];
                        case 1:
                            list = _a.sent();
                            return [2 /*return*/, list.find(function (m) { var _a; return ((_a = m.manager) === null || _a === void 0 ? void 0 : _a.id) === managerId; }) || null];
                    }
                });
            }); },
        };
        // ==================== Suppliers Service ====================
        this.suppliers = {
            list: function () { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, []];
                });
            }); },
            getById: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, null];
                });
            }); },
            create: function (data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, {}];
                });
            }); },
            update: function (id, data) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, {}];
                });
            }); },
            delete: function (id) { return __awaiter(_this, void 0, void 0, function () {
                return __generator(this, function (_a) {
                    return [2 /*return*/, {}];
                });
            }); },
        };
        this.loadTokensFromStorage();
    }
    // ==================== Token Management ====================
    DjangoAPIClient.prototype.loadTokensFromStorage = function () {
        if (typeof window === 'undefined')
            return;
        var stored = localStorage.getItem('django_tokens');
        if (stored) {
            try {
                this.tokens = JSON.parse(stored);
            }
            catch (e) {
                console.error('[v0] Failed to parse stored tokens');
            }
        }
    };
    DjangoAPIClient.prototype.saveTokensToStorage = function (tokens) {
        if (typeof window === 'undefined')
            return;
        this.tokens = tokens;
        localStorage.setItem('django_tokens', JSON.stringify(tokens));
    };
    DjangoAPIClient.prototype.clearTokensFromStorage = function () {
        if (typeof window === 'undefined')
            return;
        this.tokens = null;
        localStorage.removeItem('django_tokens');
    };
    DjangoAPIClient.prototype.refreshAccessToken = function () {
        return __awaiter(this, void 0, void 0, function () {
            var response, data_1, error_2;
            var _this = this;
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        if (!((_a = this.tokens) === null || _a === void 0 ? void 0 : _a.refresh))
                            return [2 /*return*/, null];
                        if (this.isRefreshing) {
                            return [2 /*return*/, new Promise(function (resolve) {
                                    _this.refreshQueue.push(resolve);
                                })];
                        }
                        this.isRefreshing = true;
                        _b.label = 1;
                    case 1:
                        _b.trys.push([1, 4, 5, 6]);
                        return [4 /*yield*/, fetch("".concat(API_BASE_URL, "/users/refresh/"), {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ refresh: this.tokens.refresh }),
                            })];
                    case 2:
                        response = _b.sent();
                        if (!response.ok) {
                            this.clearTokensFromStorage();
                            window.location.href = '/login';
                            return [2 /*return*/, null];
                        }
                        return [4 /*yield*/, response.json()];
                    case 3:
                        data_1 = _b.sent();
                        this.tokens = __assign(__assign({}, this.tokens), { access: data_1.access });
                        this.saveTokensToStorage(this.tokens);
                        this.refreshQueue.forEach(function (callback) { return callback(data_1.access); });
                        this.refreshQueue = [];
                        return [2 /*return*/, data_1.access];
                    case 4:
                        error_2 = _b.sent();
                        console.error('[v0] Token refresh failed:', error_2);
                        this.clearTokensFromStorage();
                        return [2 /*return*/, null];
                    case 5:
                        this.isRefreshing = false;
                        return [7 /*endfinally*/];
                    case 6: return [2 /*return*/];
                }
            });
        });
    };
    DjangoAPIClient.prototype.getAuthHeaders = function () {
        var _a;
        return __assign({ 'Content-Type': 'application/json' }, (((_a = this.tokens) === null || _a === void 0 ? void 0 : _a.access) && { Authorization: "Bearer ".concat(this.tokens.access) }));
    };
    // ==================== Core HTTP Methods ====================
    DjangoAPIClient.prototype.request = function (endpoint_1) {
        return __awaiter(this, arguments, void 0, function (endpoint, options) {
            var normalizedEndpoint, headers, requestHeaders, extraHeaders, response, newToken, error, refreshedHeaders_1, refreshedExtra, error, message;
            var _a, _b;
            if (options === void 0) { options = {}; }
            return __generator(this, function (_c) {
                switch (_c.label) {
                    case 0:
                        normalizedEndpoint = endpoint.startsWith('http')
                            ? endpoint
                            : "".concat(API_BASE_URL.replace(/\/$/, ''), "/").concat(endpoint.replace(/^\//, ''));
                        headers = this.getAuthHeaders();
                        requestHeaders = new Headers(headers);
                        extraHeaders = new Headers((_a = options.headers) !== null && _a !== void 0 ? _a : {});
                        extraHeaders.forEach(function (value, key) { return requestHeaders.set(key, value); });
                        return [4 /*yield*/, fetch(normalizedEndpoint, __assign(__assign({}, options), { headers: requestHeaders }))];
                    case 1:
                        response = _c.sent();
                        if (!(response.status === 401)) return [3 /*break*/, 6];
                        return [4 /*yield*/, this.refreshAccessToken()];
                    case 2:
                        newToken = _c.sent();
                        if (!!newToken) return [3 /*break*/, 4];
                        return [4 /*yield*/, response.json().catch(function () { return ({}); })];
                    case 3:
                        error = _c.sent();
                        throw new Error(error.detail || 'Authentication failed');
                    case 4:
                        refreshedHeaders_1 = new Headers(this.getAuthHeaders());
                        refreshedExtra = new Headers((_b = options.headers) !== null && _b !== void 0 ? _b : {});
                        refreshedExtra.forEach(function (value, key) { return refreshedHeaders_1.set(key, value); });
                        return [4 /*yield*/, fetch(normalizedEndpoint, __assign(__assign({}, options), { headers: refreshedHeaders_1 }))];
                    case 5:
                        response = _c.sent();
                        _c.label = 6;
                    case 6:
                        if (!!response.ok) return [3 /*break*/, 8];
                        return [4 /*yield*/, response.json()];
                    case 7:
                        error = (_c.sent());
                        message = error.detail
                            || (Array.isArray(error.non_field_errors) ? error.non_field_errors[0] : null)
                            || Object.entries(error).map(function (_a) {
                                var k = _a[0], v = _a[1];
                                return "".concat(k, ": ").concat(Array.isArray(v) ? v[0] : v);
                            }).join(' | ')
                            || "API Error: ".concat(response.status);
                        throw new Error(message);
                    case 8: return [2 /*return*/, response.json()];
                }
            });
        });
    };
    DjangoAPIClient.prototype.get = function (endpoint) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.request(endpoint, { method: 'GET' })];
            });
        });
    };
    DjangoAPIClient.prototype.post = function (endpoint, data) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.request(endpoint, {
                        method: 'POST',
                        body: data ? JSON.stringify(data) : undefined,
                    })];
            });
        });
    };
    DjangoAPIClient.prototype.put = function (endpoint, data) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.request(endpoint, {
                        method: 'PUT',
                        body: data ? JSON.stringify(data) : undefined,
                    })];
            });
        });
    };
    DjangoAPIClient.prototype.patch = function (endpoint, data) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.request(endpoint, {
                        method: 'PATCH',
                        body: data ? JSON.stringify(data) : undefined,
                    })];
            });
        });
    };
    DjangoAPIClient.prototype.delete = function (endpoint) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.request(endpoint, { method: 'DELETE' })];
            });
        });
    };
    // ==================== FormData Methods (for file uploads) ====================
    DjangoAPIClient.prototype.requestFormData = function (endpoint, method, data) {
        return __awaiter(this, void 0, void 0, function () {
            var url, headers, response, newToken, errorMsg, error, messages, _a;
            var _b;
            return __generator(this, function (_c) {
                switch (_c.label) {
                    case 0:
                        url = "".concat(API_BASE_URL).concat(endpoint);
                        headers = {};
                        if ((_b = this.tokens) === null || _b === void 0 ? void 0 : _b.access) {
                            headers['Authorization'] = "Bearer ".concat(this.tokens.access);
                        }
                        return [4 /*yield*/, fetch(url, { method: method, headers: headers, body: data })];
                    case 1:
                        response = _c.sent();
                        if (!(response.status === 401)) return [3 /*break*/, 4];
                        return [4 /*yield*/, this.refreshAccessToken()];
                    case 2:
                        newToken = _c.sent();
                        if (!newToken)
                            throw new Error('Authentication failed');
                        headers['Authorization'] = "Bearer ".concat(newToken);
                        return [4 /*yield*/, fetch(url, { method: method, headers: headers, body: data })];
                    case 3:
                        response = _c.sent();
                        _c.label = 4;
                    case 4:
                        if (!!response.ok) return [3 /*break*/, 9];
                        errorMsg = "API Error: ".concat(response.status);
                        _c.label = 5;
                    case 5:
                        _c.trys.push([5, 7, , 8]);
                        return [4 /*yield*/, response.json()];
                    case 6:
                        error = _c.sent();
                        messages = Object.entries(error)
                            .map(function (_a) {
                            var k = _a[0], v = _a[1];
                            return "".concat(k, ": ").concat(Array.isArray(v) ? v.join(', ') : v);
                        });
                        errorMsg = messages.join(' | ') || errorMsg;
                        return [3 /*break*/, 8];
                    case 7:
                        _a = _c.sent();
                        return [3 /*break*/, 8];
                    case 8: throw new Error(errorMsg);
                    case 9: return [2 /*return*/, response.json()];
                }
            });
        });
    };
    DjangoAPIClient.prototype.postFormData = function (endpoint, data) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.requestFormData(endpoint, 'POST', data)];
            });
        });
    };
    DjangoAPIClient.prototype.patchFormData = function (endpoint, data) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                return [2 /*return*/, this.requestFormData(endpoint, 'PATCH', data)];
            });
        });
    };
    // ==================== Token Status ====================
    DjangoAPIClient.prototype.isAuthenticated = function () {
        var _a;
        return !!((_a = this.tokens) === null || _a === void 0 ? void 0 : _a.access);
    };
    DjangoAPIClient.prototype.getAccessToken = function () {
        var _a;
        return ((_a = this.tokens) === null || _a === void 0 ? void 0 : _a.access) || null;
    };
    return DjangoAPIClient;
}());
exports.djangoClient = new DjangoAPIClient();
