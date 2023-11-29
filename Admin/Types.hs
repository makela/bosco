module Admin.Types where

import Generated.Types
import IHP.LoginSupport.Types
import IHP.ModelSupport
import IHP.Prelude

data AdminApplication = AdminApplication deriving (Eq, Show)


data StaticController = WelcomeAction deriving (Eq, Show, Data)

instance HasNewSessionUrl User where
    newSessionUrl _ = "/admin/NewSession"

type instance CurrentUserRecord = User

data SessionsController
    = NewSessionAction
    | CreateSessionAction
    | DeleteSessionAction
    deriving (Eq, Show, Data)

data ProducersController
    = ProducersAction
    | NewProducerAction
    | ShowProducerAction { producerId :: !(Id Producer) }
    | CreateProducerAction
    | EditProducerAction { producerId :: !(Id Producer) }
    | UpdateProducerAction { producerId :: !(Id Producer) }
    | DeleteProducerAction { producerId :: !(Id Producer) }
    deriving (Eq, Show, Data)

data ProductsController
    = ProductsAction
    | NewProductAction
    | ShowProductAction { productId :: !(Id Product) }
    | CreateProductAction
    | EditProductAction { productId :: !(Id Product) }
    | UpdateProductAction { productId :: !(Id Product) }
    | DeleteProductAction { productId :: !(Id Product) }
    deriving (Eq, Show, Data)

data CustomersController
    = CustomersAction
    | NewCustomerAction
    | ShowCustomerAction { customerId :: !(Id Customer) }
    | CreateCustomerAction
    | EditCustomerAction { customerId :: !(Id Customer) }
    | UpdateCustomerAction { customerId :: !(Id Customer) }
    | DeleteCustomerAction { customerId :: !(Id Customer) }
    | EmailsForDeliveryInfoAction
    | EmailsForNewsLetterAction
    deriving (Eq, Show, Data)

data OrdersController
    = OrdersAction
    | ShowOrderAction { orderId :: !(Id Order) }
    | UpdateMarkPaidOrderAction { orderId :: !(Id Order) }
    | DeleteCancelOrderAction { orderId :: !(Id Order) }
    | UpdateDeliverOrderAction { orderId :: !(Id Order) }
    | OrderedProductsAction
    deriving (Eq, Show, Data)

data WelcomeMessagesController
    = WelcomeMessagesAction
    | NewWelcomeMessageAction
    | ShowWelcomeMessageAction { welcomeMessageId :: !(Id WelcomeMessage) }
    | CreateWelcomeMessageAction
    | EditWelcomeMessageAction { welcomeMessageId :: !(Id WelcomeMessage) }
    | UpdateWelcomeMessageAction { welcomeMessageId :: !(Id WelcomeMessage) }
    | DeleteWelcomeMessageAction { welcomeMessageId :: !(Id WelcomeMessage) }
    deriving (Eq, Show, Data)

data PaymentInstructionsController
    = PaymentInstructionsAction
    | NewPaymentInstructionAction
    | ShowPaymentInstructionAction { paymentInstructionId :: !(Id PaymentInstruction) }
    | CreatePaymentInstructionAction
    | EditPaymentInstructionAction { paymentInstructionId :: !(Id PaymentInstruction) }
    | UpdatePaymentInstructionAction { paymentInstructionId :: !(Id PaymentInstruction) }
    | DeletePaymentInstructionAction { paymentInstructionId :: !(Id PaymentInstruction) }
    deriving (Eq, Show, Data)
