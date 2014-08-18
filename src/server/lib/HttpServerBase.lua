
local ServerAppBase = import(".ServerAppBase")
local HttpServerBase = class("HttpServerBase", ServerAppBase)

function HttpServerBase:ctor( config )
	HttpServerBase.super.ctor(self, config)
	self.config.requestType = "http"

	self.requestMethod = ngx.req.get_method()
	self.requestParameters = ngx.req.get_uri_args()
	if self.requestMethod == "POST" then
		ngx.req.read_body()
		table.merge(self.requestParameters, ngx.req.get_post_args())
	end

	if self.config.session then
		self.session = cc.server.Session.new(self)
	end
end
--没有加解密这一步
function HttpServerBase:process( )
	local args = self.requestParameters
	if args ~= nil then
		self:processMessage(args)
	end
end
